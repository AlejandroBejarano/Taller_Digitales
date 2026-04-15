// =============================================================================
// lcd_fsm.sv - Máquina de estados para el despliegue visual del juego Jeopardy
//
// Controla el periférico LCD (PmodCLP, HD44780) y las lecturas a las ROMs
// para mostrar:
//   - Vista de Pregunta (view_mode=0): 32 caracteres (16 línea 1 + 16 línea 2)
//     leídos de la ROM de preguntas (blk_mem_gen_0, puerto B).
//   - Vista de Opciones (view_mode=1): 32 caracteres
//     (A y C en línea 1 / B y D en línea 2) de la ROM de respuestas (blk_mem_gen_1).
//
// Botones del jugador FPGA:
//   btn_scr_i – Alterna entre vista pregunta y vista opciones.
//   btn_sel_i – Mueve el cursor de selección: A → B → C → D (módulo 4).
//   btn_ok_i  – Confirma la opción seleccionada; emite fpga_answer_valid_o.
//              Solo puede usarse una vez por ronda (flag 'answered').
//
// Protocolo con lcd_peripheral (bus de 32 bits):
//   addr=2'b00 – Registro de control: bit 0=START, bit 1=RS (0=cmd / 1=data).
//   addr=2'b01 – Registro de datos: byte a enviar al LCD (cmd o carácter).
//   Lectura de addr=2'b00: bit 8=busy, bit 9=done.
//
// Entradas:
//   clk_i          – Reloj de sistema (16 MHz).
//   rst_i          – Reset activo alto.
//   enable_i       – Pulso de 1 ciclo: CU_top ordena cargar nueva pregunta.
//   question_idx_i – Índice de la pregunta activa (0-9).
//   btn_scr_i / btn_sel_i / btn_ok_i – Botones debounceados del jugador FPGA.
//   rom_q_data_i / rom_a_data_i – Datos de ROM de preguntas / respuestas.
//   lcd_rdata_i    – Lectura del bus LCD (bits 8-9 = busy/done).
//
// Salidas:
//   fpga_answer_valid_o – Pulso de 1 ciclo: FPGA confirmó su respuesta.
//   fpga_answer_char_o  – ASCII de la letra seleccionada (A=0x41 … D=0x44).
//   rom_q_addr_o / rom_a_addr_o – Direcciones de lectura en ROMs.
//   lcd_we_o / lcd_addr_o / lcd_wdata_o – Bus de escritura al LCD.
//
// NOTA: sel_option se declara de 3 bits (para valor 4 = "ninguno" en S_CHECK_LINE_END
//       al finalizar vista pregunta). Al navegar con btn_sel, se incrementa módulo 4
//       usando máscara AND para evitar que supere 3 cuando se está en vista opciones.
//
// FSM (state_t):
//   S_IDLE              – Espera enable_i; inicializa view_mode, sel_option, answered.
//   S_START_NEW         – Resetea char_count y apunta a línea 1 del LCD.
//   S_SET_LINE1         – Envía comando Set DDRAM addr=0x80 (inicio línea 1).
//   S_WAIT_LINE1_DONE   – Espera done del LCD tras comando de línea 1.
//   S_WAIT_ROM          – Ciclo de latencia de BRAM (1 ciclo).
//   S_WRITE_CHAR        – Envía carácter leído de ROM al LCD.
//   S_WAIT_CHAR_DONE    – Espera done tras escritura de carácter.
//   S_CHECK_LINE_END    – Comprueba si hay que pasar a línea 2 o si terminó.
//   S_SET_LINE2         – Envía comando Set DDRAM addr=0xC0 (inicio línea 2).
//   S_WAIT_LINE2_DONE   – Espera done del LCD tras comando de línea 2.
//   S_INTERACTIVE       – Vista estable; atiende btn_scr, btn_sel, btn_ok.
//   S_UPDATE_CURSOR     – Envía comando de posición/tipo de cursor.
//   S_WAIT_CURSOR_DONE  – Espera done tras comando de cursor.
//   S_WAIT_BUSY_RELEASE – Sub-rutina: genera el pulso START hacia lcd_peripheral.
// =============================================================================
`timescale 1ns / 1ps

module lcd_fsm (
    input  logic        clk_i,
    input  logic        rst_i,

    // Control desde la CU maestra
    input  logic        enable_i,           // 1 = Iniciar nueva ronda (nueva pregunta)
    input  logic [3:0]  question_idx_i,     // Índice de pregunta (0-9)

    // Botones del jugador FPGA
    input  logic        btn_scr_i,          // Cambiar vista: PREGUNTA <-> OPCIONES
    input  logic        btn_sel_i,          // Mover cursor: A -> B -> C -> D
    input  logic        btn_ok_i,           // Confirmar respuesta

    // Salida hacia answer_checker / datapath
    output logic        fpga_answer_valid_o,// Pulso indicando que FPGA respondió
    output logic [7:0]  fpga_answer_char_o, // 'A', 'B', 'C' o 'D'

    // Interfaz hacia ROM de preguntas (Dual-Port Port B)
    output logic [8:0]  rom_q_addr_o,
    input  logic [7:0]  rom_q_data_i,

    // Interfaz hacia ROM de respuestas (Dual-Port Port B)
    output logic [8:0]  rom_a_addr_o,
    input  logic [7:0]  rom_a_data_i,

    // Bus hacia lcd_peripheral
    output logic        lcd_we_o,
    output logic [1:0]  lcd_addr_o,
    output logic [31:0] lcd_wdata_o,
    input  logic [31:0] lcd_rdata_i         // bit 9 es 'done', bit 8 es 'busy'
);

    // =========================================================================
    // Estados principales
    // =========================================================================
    typedef enum logic [4:0] {
        S_IDLE,
        S_START_NEW,
        S_SET_LINE1,
        S_WAIT_LINE1_DONE,
        S_WRITE_CHAR,
        S_WAIT_ROM,
        S_WAIT_CHAR_DONE,
        S_CHECK_LINE_END,
        S_SET_LINE2,
        S_WAIT_LINE2_DONE,
        S_INTERACTIVE,
        S_UPDATE_CURSOR,
        S_WAIT_CURSOR_DONE,
        S_WAIT_BUSY_RELEASE    // Sub-estado: genera pulso START al lcd_peripheral
    } state_t;

    state_t state, return_state;

    // view_mode  – 0 = mostrando pregunta, 1 = mostrando opciones
    // sel_option – 3 bits; valores 0-3 = A/B/C/D; valor 4 = ninguno (cursor off)
    // answered   – 1 = el jugador FPGA ya confirmó su respuesta esta ronda
    // char_count – contador de bytes leídos de ROM en la vista actual (0-31)
    // base_addr  – dirección base = question_idx * 32
    logic       view_mode;
    logic [2:0] sel_option;
    logic       answered;
    logic [4:0] char_count;
    logic [8:0] base_addr;

    // Alias de señales de estado del LCD (del registro de control, lectura)
    logic lcd_done;
    logic lcd_busy;
    assign lcd_done = lcd_rdata_i[9];
    assign lcd_busy = lcd_rdata_i[8];

    // =========================================================================
    // Direcciones de ROM: base fija por pregunta + offset del contador de bytes
    // Ambas ROMs usan el mismo esquema de dirección; la FSM elige cuál usar
    // en S_WRITE_CHAR según view_mode.
    // =========================================================================
    assign rom_q_addr_o = base_addr + {4'b0, char_count};
    assign rom_a_addr_o = base_addr + {4'b0, char_count};

    // =========================================================================
    // Conversión sel_option (0-3) → carácter ASCII para fpga_answer_char_o
    // sel_option=4 (ninguno) cae en default; en ese caso el checker no se activa
    // porque fpga_answer_valid_o no se emitirá mientras answered=0.
    // =========================================================================
    always_comb begin
        case (sel_option)
            2'd0: fpga_answer_char_o = 8'h41; // A
            2'd1: fpga_answer_char_o = 8'h42; // B
            2'd2: fpga_answer_char_o = 8'h43; // C
            2'd3: fpga_answer_char_o = 8'h44; // D
            default: fpga_answer_char_o = 8'h41; // Default A
        endcase
    end

    // =========================================================================
    // Lógica secuencial FSM
    // =========================================================================
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state               <= S_IDLE;
            view_mode           <= 1'b0;
            sel_option          <= 2'd0;
            answered            <= 1'b0;
            char_count          <= 5'd0;
            base_addr           <= 9'd0;
            fpga_answer_valid_o <= 1'b0;
            lcd_we_o            <= 1'b0;
            lcd_addr_o          <= 2'b00;
            lcd_wdata_o         <= 32'd0;
        end else begin
            fpga_answer_valid_o <= 1'b0;
            lcd_we_o            <= 1'b0;

            case (state)

                // Esperar enable_i de CU_top (nueva pregunta)
                S_IDLE: begin
                    if (enable_i) begin
                        view_mode  <= 1'b0;          // Empieza mostrando pregunta
                        sel_option <= 2'd0;          // Resetea cursor a A
                        answered   <= 1'b0;
                        base_addr  <= {question_idx_i, 5'b0_0000}; // idx * 32
                        state      <= S_START_NEW;
                    end
                end

                // Resetear contador de caracteres antes de dibujar la pantalla
                S_START_NEW: begin
                    char_count <= 5'd0;
                    state      <= S_SET_LINE1;
                end

                // Enviar comando Set DDRAM addr=0x80 (cursor al inicio de línea 1)
                S_SET_LINE1: begin
                    if (!lcd_busy) begin
                        lcd_we_o    <= 1'b1;
                        lcd_addr_o  <= 2'b01;          // Registro de datos (byte de cmd)
                        lcd_wdata_o <= 32'h80;         // DDRAM Address L1 = 0x00 → cmd 0x80

                        return_state <= S_WAIT_LINE1_DONE;
                        state        <= S_WAIT_BUSY_RELEASE;
                    end
                end

                // Esperar done del LCD tras el comando de línea 1
                S_WAIT_LINE1_DONE: begin
                    if (lcd_done) begin
                        state <= S_WAIT_ROM;
                    end else begin
                        lcd_addr_o <= 2'b00; // Seguir leyendo ctrl reg para polling
                    end
                end

                // Ciclo de latencia BRAM: el dato de ROM estará disponible en el siguiente estado
                S_WAIT_ROM: begin
                    state <= S_WRITE_CHAR;
                end

                // Enviar carácter leído de ROM al LCD
                // Selecciona entre ROM de preguntas y ROM de respuestas según view_mode
                S_WRITE_CHAR: begin
                    if (!lcd_busy) begin
                        lcd_we_o    <= 1'b1;
                        lcd_addr_o  <= 2'b01;
                        lcd_wdata_o <= {24'b0, (view_mode == 0) ? rom_q_data_i : rom_a_data_i};

                        return_state <= S_WAIT_CHAR_DONE;
                        state        <= S_WAIT_BUSY_RELEASE;
                    end
                end

                // Esperar done del LCD tras enviar el carácter
                S_WAIT_CHAR_DONE: begin
                    if (lcd_done) begin
                        state <= S_CHECK_LINE_END;
                    end else begin
                        lcd_addr_o <= 2'b00;
                    end
                end

                // Verificar si hay que pasar a línea 2 o si ya se dibujaron los 32 chars
                S_CHECK_LINE_END: begin
                    if (char_count == 5'd15) begin
                        // Completada línea 1 (chars 0-15): pasar a línea 2
                        char_count <= char_count + 1;
                        state      <= S_SET_LINE2;
                    end else if (char_count == 5'd31) begin
                        // Completadas ambas líneas (chars 0-31)
                        if (view_mode == 1'b1) begin
                            // Vista opciones: posicionar cursor blinker en opción A
                            state <= S_UPDATE_CURSOR;
                        end else begin
                            // Vista pregunta: apagar cursor (sel_option=4 → cmd 0x0C en S_UPDATE_CURSOR)
                            sel_option <= 3'd4;
                            state <= S_UPDATE_CURSOR;
                        end
                    end else begin
                        char_count <= char_count + 1;
                        state      <= S_WAIT_ROM;
                    end
                end

                // Enviar comando Set DDRAM addr=0xC0 (cursor al inicio de línea 2)
                S_SET_LINE2: begin
                    if (!lcd_busy) begin
                        lcd_we_o    <= 1'b1;
                        lcd_addr_o  <= 2'b01;
                        lcd_wdata_o <= 32'hC0; // DDRAM Address L2 = 0x40 → cmd 0x80|0x40

                        return_state <= S_WAIT_LINE2_DONE;
                        state        <= S_WAIT_BUSY_RELEASE;
                    end
                end

                // Esperar done del LCD tras el comando de línea 2
                S_WAIT_LINE2_DONE: begin
                    if (lcd_done) begin
                        state <= S_WAIT_ROM;
                    end else begin
                        lcd_addr_o <= 2'b00;
                    end
                end

                // Estado interactivo: atender botones del jugador FPGA
                S_INTERACTIVE: begin
                    if (btn_scr_i) begin
                        // Alternar entre vista pregunta y opciones; redibujar pantalla
                        view_mode <= ~view_mode;
                        state     <= S_START_NEW;
                    end
                    else if (btn_sel_i) begin
                        // Navegar: A(0)→B(1)→C(2)→D(3)→A(0) módulo 4
                        sel_option <= (sel_option == 3'd3) ? 3'd0 : sel_option + 3'd1;
                        if (view_mode == 1'b1) begin
                            // Solo actualizar posición del cursor si estamos en vista opciones
                            state <= S_UPDATE_CURSOR;
                        end
                    end
                    else if (btn_ok_i && !answered) begin
                        // Confirmar respuesta: emitir pulso de 1 ciclo
                        answered            <= 1'b1;
                        fpga_answer_valid_o <= 1'b1;
                    end
                end

                // Enviar comando de posición de cursor o comando de display ON/cursor OFF
                // Para vista opciones: posiciona el cursor en la opción seleccionada.
                // Para vista pregunta: envía 0x0C (display on, cursor off, no blink).
                S_UPDATE_CURSOR: begin
                    if (!lcd_busy) begin
                        lcd_we_o   <= 1'b1;
                        lcd_addr_o <= 2'b01; // Registro de datos (cmd)

                        if (view_mode == 1'b0) begin
                            // Vista pregunta: apagar cursor → cmd 0x0C
                            lcd_wdata_o <= 32'h0C;
                        end else begin
                            // Vista opciones: posición DDRAM según opción elegida
                            // A(0)→0x80, B(1)→0xC0, C(2)→0x88, D(3)→0xC8
                            case (sel_option)
                                3'd0: lcd_wdata_o <= 32'h80; // A: inicio línea 1
                                3'd1: lcd_wdata_o <= 32'hC0; // B: inicio línea 2
                                3'd2: lcd_wdata_o <= 32'h88; // C: col 8 línea 1
                                3'd3: lcd_wdata_o <= 32'hC8; // D: col 8 línea 2
                                default: lcd_wdata_o <= 32'h0C;
                            endcase
                        end

                        return_state <= S_WAIT_CURSOR_DONE;
                        state        <= S_WAIT_BUSY_RELEASE;
                    end
                end

                // Esperar done tras el comando de cursor
                S_WAIT_CURSOR_DONE: begin
                    if (lcd_done) begin
                        state <= S_INTERACTIVE;
                    end else begin
                        lcd_addr_o <= 2'b00;
                    end
                end

                // Sub-rutina: genera el pulso START (bit 0) en el registro de control
                // del LCD. El bit RS (bit 1) indica si es dato (1) o comando (0).
                // Se llama desde cualquier estado que necesite finalizar una escritura.
                S_WAIT_BUSY_RELEASE: begin
                    lcd_we_o   <= 1'b1;
                    lcd_addr_o <= 2'b00; // Registro de control
                    if (return_state == S_WAIT_CHAR_DONE) begin
                         lcd_wdata_o <= {30'b0, 1'b1, 1'b1}; // RS=1 (dato), START=1
                    end else begin
                         lcd_wdata_o <= {30'b0, 1'b0, 1'b1}; // RS=0 (comando), START=1
                    end
                    state <= return_state;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
