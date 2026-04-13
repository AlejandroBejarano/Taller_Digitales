// =============================================================================
// Proyecto : EL3313 Proyecto 2 - Jeopardy! (I Semestre 2026)
// Archivo  : lcd_newlogic.sv
// Descripción:
//   Periférico LCD completo para PmodCLP (HD44780).
//   Cumple la interfaz estándar de 32 bits del PDF (sección 3.4.3).
//   Las memorias de preguntas y opciones se inicializan desde archivos .coe
//   sintetizables en Vivado 2025.2 mediante IP Block Memory Generator.
//
// Organización SOLID de módulos:
//   1. lcd_question_rom   - SRP: ROM de enunciados (all_questions.coe)
//   2. lcd_option_rom     - SRP: ROM de opciones   (all_opt_questions.coe)
//   3. lcd_register_file  - SRP: Registros de control/estado/datos del periférico
//   4. lcd_driver_hw      - SRP: Controlador físico HD44780 (temporización 16 MHz)
//   5. lcd_peripheral     - Top: Integra los cuatro módulos anteriores
//
// Principios SOLID aplicados:
//   S - Cada módulo tiene una única responsabilidad.
//   O - Los módulos internos son cerrados a modificación; se extiende instanciando.
//   L - lcd_peripheral puede sustituirse por cualquier wrapper con la misma interfaz.
//   I - La interfaz estándar de 32 bits es mínima y bien definida.
//   D - lcd_peripheral depende de abstracciones (puertos), no de detalles internos.
//
// Notas de síntesis:
//   • lcd_question_rom y lcd_option_rom deben inferir BRAM con init file .coe.
//     En Vivado: Project Settings → Synthesis → -rom_style block  (o usar IP BMG).
//   • El archivo .coe debe apuntar al mismo directorio o configurarse en el IP.
//   • Reloj único de 16 MHz generado externamente por PLL desde 100 MHz.
// =============================================================================
`timescale 1ns / 1ps

// =============================================================================
// Módulo 1: lcd_question_rom
// Responsabilidad única: almacenar y exponer los bytes de los enunciados de
// pregunta (all_questions.coe, 320 bytes, radix 16).
//
// Mapa de memoria:
//   Cada pregunta ocupa 32 bytes (índices 0..31).
//   question_num ∈ [0..9]  →  base = question_num * 32
//   question_off ∈ [0..31] →  dirección = base + question_off
//
// Parámetros:
//   DEPTH  : número total de palabras (320)
//   WIDTH  : ancho de palabra en bits (8)
//   COE_FILE: ruta relativa al .coe (se pasa como parámetro para flexibilidad)
// =============================================================================
module lcd_question_rom #(
    parameter integer DEPTH    = 320,
    parameter integer WIDTH    = 8,
    parameter string  COE_FILE = "all_questions.coe"
)(
    input  logic                      clk,
    input  logic [$clog2(DEPTH)-1:0]  addr,   // 0..319
    output logic [WIDTH-1:0]          data_o
);
    (* rom_style = "block" *)
    logic [WIDTH-1:0] mem [0:DEPTH-1];

    // Inicialización sintetizable en Vivado: usa $readmemh con archivo .mem
    // equivalente, o instancia directamente el IP Block Memory Generator con
    // el .coe correspondiente. Aquí se usa readmemh como respaldo portable;
    // para síntesis real, reemplazar este bloque por el IP BMG y conectar sus
    // puertos a (clk, addr, data_o).
    initial $readmemh(COE_FILE, mem);

    always_ff @(posedge clk)
        data_o <= mem[addr];

endmodule


// =============================================================================
// Módulo 2: lcd_option_rom
// Responsabilidad única: almacenar y exponer los bytes de opciones A/B/C/D
// (all_opt_questions.coe, 320 bytes, radix 16).
//
// Mapa de memoria:
//   Cada pregunta ocupa 32 bytes de opciones.
//   question_num ∈ [0..9]  →  base = question_num * 32
//   question_off ∈ [0..31] →  dirección = base + question_off
// =============================================================================
module lcd_option_rom #(
    parameter integer DEPTH    = 320,
    parameter integer WIDTH    = 8,
    parameter string  COE_FILE = "all_opt_questions.coe"
)(
    input  logic                      clk,
    input  logic [$clog2(DEPTH)-1:0]  addr,   // 0..319
    output logic [WIDTH-1:0]          data_o
);
    (* rom_style = "block" *)
    logic [WIDTH-1:0] mem [0:DEPTH-1];

    initial $readmemh(COE_FILE, mem);

    always_ff @(posedge clk)
        data_o <= mem[addr];

endmodule


// =============================================================================
// Módulo 3: lcd_register_file
// Responsabilidad única: implementar el banco de registros del periférico
// (Registro 0 CONTROL/ESTADO y Registro 1 DATOS) según sección 3.4.1 del PDF.
//
// Interfaz:
//   Escritura: write_enable_i=1, addr_i, wdata_i → actualiza registros internos
//   Lectura  : write_enable_i=0, addr_i          → devuelve rdata_o
//
// Bits expuestos (Registro 0):
//   bit 0 → pulse_start  (W1P)
//   bit 1 → reg_rs       (rw)
//   bit 2 → pulse_clear  (W1P)
//   bit 3 → pulse_home   (W1P)
//   bit 8 → hw_busy      (RO, entrada)
//   bit 9 → done_flag    (RO, capturado internamente de hw_done)
//
// Bits expuestos (Registro 1):
//   bits [7:0] → reg_data (rw)
// =============================================================================
module lcd_register_file (
    input  logic        clk_i,
    input  logic        rst_i,
    // Interfaz estándar (sección 3.4.3)
    input  logic        write_enable_i,
    input  logic [1:0]  addr_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    // Señales de control hacia el driver físico
    output logic        pulse_start,
    output logic        pulse_clear,
    output logic        pulse_home,
    output logic        reg_rs,
    output logic [7:0]  reg_data,
    // Señales de estado desde el driver físico
    input  logic        hw_busy,
    input  logic        hw_done
);
    logic done_flag;

    // --- Lógica de escritura (síncrona) ---
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            reg_rs      <= 1'b0;
            reg_data    <= 8'h00;
            pulse_start <= 1'b0;
            pulse_clear <= 1'b0;
            pulse_home  <= 1'b0;
            done_flag   <= 1'b0;
        end else begin
            // Pulsos W1P: duran exactamente 1 ciclo de reloj
            pulse_start <= 1'b0;
            pulse_clear <= 1'b0;
            pulse_home  <= 1'b0;

            // Capturar flanco de finalización del driver físico
            if (hw_done)
                done_flag <= 1'b1;

            if (write_enable_i) begin
                case (addr_i)
                    2'b00: begin // Registro 0: CONTROL/ESTADO
                        pulse_start <= wdata_i[0]; // bit 0: start  (W1P)
                        reg_rs      <= wdata_i[1]; // bit 1: rs
                        pulse_clear <= wdata_i[2]; // bit 2: clear  (W1P)
                        pulse_home  <= wdata_i[3]; // bit 3: home   (W1P)
                        // Nueva operación → limpia done_flag
                        if (wdata_i[0] | wdata_i[2] | wdata_i[3])
                            done_flag <= 1'b0;
                    end
                    2'b01: begin // Registro 1: DATOS
                        reg_data <= wdata_i[7:0];  // bits [7:0]: data byte
                    end
                    default: ; // Direcciones 2'b10 y 2'b11 reservadas
                endcase
            end
        end
    end

    // --- Lógica de lectura (combinacional) ---
    always_comb begin
        rdata_o = 32'h00000000;
        case (addr_i)
            2'b00: begin // Lectura del Registro de Control/Estado
                rdata_o[1] = reg_rs;
                rdata_o[8] = hw_busy;   // bit 8: busy (RO)
                rdata_o[9] = done_flag; // bit 9: done (RO)
            end
            2'b01: begin // Lectura del Registro de Datos
                rdata_o[7:0] = reg_data;
            end
            default: rdata_o = 32'h00000000;
        endcase
    end

endmodule


// =============================================================================
// Módulo 4: lcd_driver_hw
// Responsabilidad única: generar las señales físicas hacia el PmodCLP/HD44780.
// Gestiona temporización interna (tick de 1 µs a 16 MHz) y la máquina de
// estados de control del Enable, sin conocer la lógica del periférico.
//
// FSM:
//   WAIT_DELAY   → espera inicial de 50 ms (power-on)
//   IDLE         → espera solicitud
//   SETUP        → carga datos en bus y activa lcd_e
//   TOGGLE_E_HIGH→ mantiene lcd_e activo ≥ 450 ns (2 ticks de 1 µs)
//   TOGGLE_E_LOW → espera tiempo de ejecución del comando (50 µs ó 2 ms)
// =============================================================================
module lcd_driver_hw (
    input  logic       clk,
    input  logic       rst,
    // Peticiones desde el registro de control
    input  logic       start_req,
    input  logic       clear_req,
    input  logic       home_req,
    input  logic [7:0] data_in,
    input  logic       rs_in,
    // Estado hacia el registro de control
    output logic       busy,
    output logic       done_pulse,
    // Interfaz física PmodCLP
    output logic       lcd_rs,
    output logic       lcd_rw,
    output logic       lcd_e,
    output logic [7:0] lcd_d
);
    // lcd_rw siempre en escritura (HD44780 en modo write-only)
    assign lcd_rw = 1'b0;

    // --- Generador de tick de 1 µs (16 ciclos de 16 MHz = 1 µs) ---
    localparam integer TICKS_PER_US = 16;

    logic [3:0] tick_cnt;
    logic       tick_1us;

    always_ff @(posedge clk) begin
        if (rst) begin
            tick_cnt <= 4'd0;
            tick_1us <= 1'b0;
        end else if (tick_cnt == TICKS_PER_US - 1) begin
            tick_cnt <= 4'd0;
            tick_1us <= 1'b1;
        end else begin
            tick_cnt <= tick_cnt + 1'b1;
            tick_1us <= 1'b0;
        end
    end

    // --- FSM principal ---
    typedef enum logic [2:0] {
        WAIT_DELAY,
        IDLE,
        SETUP,
        TOGGLE_E_HIGH,
        TOGGLE_E_LOW
    } drv_state_t;

    drv_state_t state;
    logic [19:0] delay;

    // Delays en microsegundos
    localparam integer DELAY_POWERON_US = 20'd50000; // 50 ms
    localparam integer DELAY_SLOW_US    = 20'd2000;  // 2 ms  (clear, home, cursor cmds)
    localparam integer DELAY_FAST_US    = 20'd50;    // 50 µs (escritura de dato/char)
    localparam integer DELAY_ENABLE_US  = 20'd2;     // 2 µs  (ancho pulso E ≥ 450 ns)

    always_ff @(posedge clk) begin
        if (rst) begin
            state      <= WAIT_DELAY;
            busy       <= 1'b1;
            done_pulse <= 1'b0;
            lcd_e      <= 1'b0;
            lcd_rs     <= 1'b0;
            lcd_d      <= 8'h00;
            delay      <= DELAY_POWERON_US;
        end else begin
            done_pulse <= 1'b0; // Pulso de un solo ciclo por defecto

            if (tick_1us) begin
                case (state)

                    // ----------------------------------------------------------
                    IDLE: begin
                        busy <= 1'b0;
                        if (start_req | clear_req | home_req) begin
                            busy <= 1'b1;
                            if (clear_req) begin
                                lcd_rs <= 1'b0;
                                lcd_d  <= 8'h01; // Comando Clear Display
                                delay  <= DELAY_SLOW_US;
                            end else if (home_req) begin
                                lcd_rs <= 1'b0;
                                lcd_d  <= 8'h02; // Comando Return Home
                                delay  <= DELAY_SLOW_US;
                            end else begin
                                lcd_rs <= rs_in;
                                lcd_d  <= data_in;
                                // Comandos de cursor/posición (≤0x03) son lentos
                                delay  <= (~rs_in & (data_in <= 8'h03))
                                          ? DELAY_SLOW_US : DELAY_FAST_US;
                            end
                            state <= SETUP;
                        end
                    end

                    // ----------------------------------------------------------
                    SETUP: begin
                        lcd_e <= 1'b1;
                        delay <= DELAY_ENABLE_US;
                        state <= TOGGLE_E_HIGH;
                    end

                    // ----------------------------------------------------------
                    TOGGLE_E_HIGH: begin
                        if (delay == 20'd0) begin
                            lcd_e <= 1'b0;
                            // delay ya tiene el valor de ejecución asignado en IDLE
                            state <= TOGGLE_E_LOW;
                        end else
                            delay <= delay - 1'b1;
                    end

                    // ----------------------------------------------------------
                    TOGGLE_E_LOW: begin
                        if (delay == 20'd0) begin
                            done_pulse <= 1'b1;
                            state      <= IDLE;
                        end else
                            delay <= delay - 1'b1;
                    end

                    // ----------------------------------------------------------
                    WAIT_DELAY: begin // Power-on delay
                        if (delay == 20'd0) begin
                            done_pulse <= 1'b1;
                            state      <= IDLE;
                        end else
                            delay <= delay - 1'b1;
                    end

                    default: state <= IDLE;
                endcase
            end
        end
    end

endmodule


// =============================================================================
// Módulo 5 (Top): lcd_peripheral
// Responsabilidad única: integrar los cuatro módulos anteriores y exponer la
// interfaz estándar de 32 bits (sección 3.4.3) más los puertos de consulta ROM.
//
// Puertos de ROM (question_num, question_off, question_byte_o, option_byte_o):
//   Permiten que la lógica de control del juego lea cualquier byte de los
//   enunciados y opciones sin acceder directamente a las memorias.
//   La dirección ROM se calcula como:  question_num*32 + question_off
//
//   • question_num ∈ [0..9]  (4 bits, representa las 10 preguntas del banco)
//   • question_off ∈ [0..31] (5 bits, desplazamiento dentro de los 32 bytes)
//
// Cambio respecto al original:
//   Las ROMs ahora se implementan dentro de este archivo con lcd_question_rom
//   y lcd_option_rom (inferencia de BRAM con .coe), en lugar de depender de
//   archivos .mem externos leídos con $readmemh en el nivel superior.
//   Para síntesis en Vivado, reemplaza los módulos de ROM por instancias de
//   IP Block Memory Generator apuntando a los .coe (ver nota al inicio del archivo).
// =============================================================================
module lcd_peripheral (
    // Interfaz estándar de 32 bits (sección 3.4.3)
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic        write_enable_i,
    input  logic [1:0]  addr_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,

    // Interfaz física hacia el PmodCLP
    output logic        lcd_rs,
    output logic        lcd_rw,
    output logic        lcd_e,
    output logic [7:0]  lcd_d,

    // Puertos de consulta ROM (sin cambio respecto al original)
    input  logic [3:0]  question_num,   // 0..9 (índice de pregunta)
    input  logic [4:0]  question_off,   // 0..31 (byte dentro de la pregunta)
    output logic [7:0]  question_byte_o,
    output logic [7:0]  option_byte_o
);

    // -------------------------------------------------------------------------
    // Señales internas entre módulos
    // -------------------------------------------------------------------------
    logic        pulse_start, pulse_clear, pulse_home;
    logic        reg_rs;
    logic [7:0]  reg_data;
    logic        hw_busy, hw_done;

    // Dirección ROM: question_num*32 + question_off (9 bits cubre 0..319)
    logic [8:0] rom_addr;
    assign rom_addr = {question_num, question_off}; // == question_num*32 + question_off

    // -------------------------------------------------------------------------
    // Módulo 1: ROM de enunciados de preguntas
    // -------------------------------------------------------------------------
    lcd_question_rom #(
        .DEPTH    (320),
        .WIDTH    (8),
        .COE_FILE ("all_questions.coe")
    ) u_question_rom (
        .clk    (clk_i),
        .addr   (rom_addr),
        .data_o (question_byte_o)
    );

    // -------------------------------------------------------------------------
    // Módulo 2: ROM de opciones A/B/C/D
    // -------------------------------------------------------------------------
    lcd_option_rom #(
        .DEPTH    (320),
        .WIDTH    (8),
        .COE_FILE ("all_opt_questions.coe")
    ) u_option_rom (
        .clk    (clk_i),
        .addr   (rom_addr),
        .data_o (option_byte_o)
    );

    // -------------------------------------------------------------------------
    // Módulo 3: Banco de registros del periférico
    // -------------------------------------------------------------------------
    lcd_register_file u_regfile (
        .clk_i          (clk_i),
        .rst_i          (rst_i),
        .write_enable_i (write_enable_i),
        .addr_i         (addr_i),
        .wdata_i        (wdata_i),
        .rdata_o        (rdata_o),
        .pulse_start    (pulse_start),
        .pulse_clear    (pulse_clear),
        .pulse_home     (pulse_home),
        .reg_rs         (reg_rs),
        .reg_data       (reg_data),
        .hw_busy        (hw_busy),
        .hw_done        (hw_done)
    );

    // -------------------------------------------------------------------------
    // Módulo 4: Driver físico HD44780
    // -------------------------------------------------------------------------
    lcd_driver_hw u_driver_hw (
        .clk        (clk_i),
        .rst        (rst_i),
        .start_req  (pulse_start),
        .clear_req  (pulse_clear),
        .home_req   (pulse_home),
        .data_in    (reg_data),
        .rs_in      (reg_rs),
        .busy       (hw_busy),
        .done_pulse (hw_done),
        .lcd_rs     (lcd_rs),
        .lcd_rw     (lcd_rw),
        .lcd_e      (lcd_e),
        .lcd_d      (lcd_d)
    );

endmodule