`timescale 1ns / 1ps
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

    // CAMBIO: Se cambio la inferencia de BRAM con atributo (* rom_style = "block" *)
    // y $readmemh por la instanciacion del IP de Vivado 'blk_mem_questions' porque
    // $readmemh con archivos .coe no es soportado nativamente para simulacion y
    // causaba valores XX.
    // CAMBIO: se agrego .ena(1'b1) porque el puerto ena del IP Block Memory
    // Generator requiere conexion explicita; sin ella Vivado genera warning
    // VRFC 10-5021 y en algunos modos de sintesis la memoria queda deshabilitada.
    blk_mem_questions ip_rom_questions (
        .clka  (clk),
        .ena   (1'b1),
        .addra (addr),
        .douta (data_o)
    );

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

    // CAMBIO: Se cambio la inferencia de BRAM con atributo (* rom_style = "block" *)
    // y $readmemh por la instanciacion del IP de Vivado 'blk_mem_options' porque
    // $readmemh con archivos .coe no es soportado nativamente para simulacion y
    // causaba valores XX.
    // CAMBIO: se agrego .ena(1'b1) - misma razon que en blk_mem_questions.
    blk_mem_options ip_rom_options (
        .clka  (clk),
        .ena   (1'b1),
        .addra (addr),
        .douta (data_o)
    );

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
// (Sin cambios estructurales, se mantiene idéntico al original)
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
// CAMBIO: Se agrego el parametro POWERON_US con valor por defecto 50000 porque
// permite al testbench sobreescribirlo a 100 para acelerar la simulacion sin
// afectar el comportamiento real en hardware.
module lcd_driver_hw #(
    parameter integer POWERON_US = 50000
)(
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

    // CAMBIO: Se agrego exec_delay porque en el original SETUP sobreescribia
    // el delay asignado en IDLE con DELAY_ENABLE_US, causando que el tiempo de
    // ejecucion del comando no se respetara en TOGGLE_E_LOW.
    logic [19:0] exec_delay;

    // Delays en microsegundos
    // CAMBIO: DELAY_POWERON_US ahora usa el parametro POWERON_US en lugar del
    // literal 20'd50000 porque permite configurarlo externamente desde el testbench.
    localparam integer DELAY_POWERON_US = POWERON_US;
    localparam integer DELAY_SLOW_US    = 20'd2000;  // 2 ms  (clear, home, cursor cmds)
    localparam integer DELAY_FAST_US    = 20'd50;    // 50 µs (escritura de dato/char)
    localparam integer DELAY_ENABLE_US  = 20'd2;     // 2 µs  (ancho pulso E >= 450 ns)

    // =========================================================================
    // CAMBIO: Se agregaron registros de latch (req_latched, clear_latched,
    // home_latched, latched_data, latched_rs) en lugar de leer start_req,
    // clear_req y home_req directamente en el estado IDLE, porque IDLE solo
    // se evalua cuando tick_1us=1 (una vez cada 16 ciclos de reloj). Los
    // pulsos provenientes de lcd_register_file duran exactamente 1 ciclo, por
    // lo que hay una probabilidad de 15/16 de que el request ocurra en un
    // ciclo donde tick_1us=0 y el comando se pierda. Esto causaba que en
    // simulacion post-sintesis el LCD nunca completara escrituras y la tarea
    // lcd_wait_done del testbench iterara hasta el timeout (31 ms por llamada),
    // agotando el budget de 200 ms de simulacion antes del test UART.
    // =========================================================================
    logic       req_latched;
    logic       clear_latched;
    logic       home_latched;
    logic [7:0] latched_data;
    logic       latched_rs;

    //CAMBIO: se invirtio el orden CLEAR/SET dentro del bloque always_ff por
    //SET primero y CLEAR al final porque con asignaciones no bloqueantes (NBA)
    //la ultima asignacion gana; con el orden anterior, si start_req llegaba
    //en el mismo ciclo en que IDLE aceptaba el request previo, el CLEAR
    //(que estaba al final) ganaba y el nuevo request se perdia silenciosamente.
    always_ff @(posedge clk) begin
        if (rst) begin
            req_latched   <= 1'b0;
            clear_latched <= 1'b0;
            home_latched  <= 1'b0;
            latched_data  <= 8'h00;
            latched_rs    <= 1'b0;
        end else begin
            // Limpiar latches cuando IDLE acepta la solicitud (menor prioridad)
            if (tick_1us && (state == IDLE) &&
                (req_latched | clear_latched | home_latched)) begin
                req_latched   <= 1'b0;
                clear_latched <= 1'b0;
                home_latched  <= 1'b0;
            end
            // Capturar request en cualquier flanco - va al final para ganar
            // sobre el CLEAR si ambas condiciones ocurren en el mismo ciclo
            if (start_req) begin
                req_latched  <= 1'b1;
                latched_data <= data_in;
                latched_rs   <= rs_in;
            end
            if (clear_req) clear_latched <= 1'b1;
            if (home_req)  home_latched  <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state      <= WAIT_DELAY;
            busy       <= 1'b1;
            done_pulse <= 1'b0;
            lcd_e      <= 1'b0;
            lcd_rs     <= 1'b0;
            lcd_d      <= 8'h00;
            delay      <= DELAY_POWERON_US;
            exec_delay <= 20'd0; // CAMBIO: Se agrego reset de exec_delay porque es un registro nuevo
        end else begin
            done_pulse <= 1'b0; // Pulso de un solo ciclo por defecto

            if (tick_1us) begin
                case (state)

                    // ----------------------------------------------------------
                    // CAMBIO: Se cambio start_req|clear_req|home_req por
                    // req_latched|clear_latched|home_latched porque los pulsos
                    // directos de 1 ciclo no coinciden con tick_1us (cada 16
                    // ciclos). Se usan latched_data y latched_rs en vez de
                    // data_in y rs_in para garantizar datos estables al procesar.
                    IDLE: begin
                        busy <= 1'b0;
                        if (req_latched | clear_latched | home_latched) begin
                            busy <= 1'b1;
                            if (clear_latched) begin
                                lcd_rs <= 1'b0;
                                lcd_d  <= 8'h01; // Comando Clear Display
                                exec_delay <= DELAY_SLOW_US;
                            end else if (home_latched) begin
                                lcd_rs <= 1'b0;
                                lcd_d  <= 8'h02; // Comando Return Home
                                exec_delay <= DELAY_SLOW_US;
                            end else begin // req_latched (start)
                                lcd_rs <= latched_rs;
                                lcd_d  <= latched_data;
                                // Comandos de cursor/posicion (<=0x03) son lentos
                                exec_delay <= (~latched_rs & (latched_data <= 8'h03))
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
                            delay <= exec_delay; // CAMBIO: Se carga exec_delay en lugar de reutilizar delay porque SETUP lo habia sobreescrito con DELAY_ENABLE_US
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
// =============================================================================
// CAMBIO: Se agrego el parametro POWERON_US porque permite propagarlo al driver
// fisico desde peripheral_top para que el testbench pueda acortar el retardo
// de encendido sin modificar el codigo interno del driver.
module lcd_peripheral #(
    parameter integer POWERON_US = 50000
)(
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
    // CAMBIO: Se instancio el driver pasando el parametro POWERON_US porque
    // en el codigo B no existia este parametro y el valor de power-on estaba
    // fijo como literal dentro del driver sin posibilidad de configuracion externa.
    // -------------------------------------------------------------------------
    lcd_driver_hw #(
        .POWERON_US (POWERON_US)
    ) u_driver_hw (
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