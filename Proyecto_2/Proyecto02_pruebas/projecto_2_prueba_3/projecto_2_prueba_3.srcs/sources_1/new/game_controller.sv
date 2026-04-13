`timescale 1ns / 1ps
//CAMBIO: se rediseño completamente el modulo game_controller porque el original:
// 1) Usaba un bus compartido (sel_uart, sel_lcd, bus_addr, bus_wdata) que no
//    existe en peripheral_top; los puertos reales son UART y LCD completamente
//    separados.
// 2) Avanzaba de ST_GAME_RUN a ST_CHECK con btn_sel en vez de esperar la senal
//    pt (punto asignado) o no_answer (timeout sin respuesta) del datapath.
// 3) No esperaba uart_tx_done_i para confirmar envio completo.
// 4) No tenia salidas para el buzzer ni para activar game_running_o.

module game_controller (
    input  logic        clk,
    input  logic        rst,

    // --- Interfaz con el datapath (topLFSRandcompany) ---
    input  logic        ready_question,   // question_selector: nueva pregunta disponible
    input  logic [3:0]  question_idx,     // indice de la pregunta activa (0-9)
    output logic        enable_rng,       // habilita generacion de pregunta siguiente
    input  logic        round_done,       // 7 preguntas completadas: fin de juego
    input  logic        pt,              // se asigno un punto en esta ronda
    input  logic        no_answer,        // nadie respondio en el tiempo de la ronda

    // --- Interfaz UART (peripheral_top: puertos reales) ---
    output logic        uart_start_tx_o,  // pulso para iniciar transmision
    output logic [31:0] uart_base_addr_o, // direccion base en ROM de la pregunta
    input  logic        uart_tx_done_i,   // transmision completada
    input  logic        uart_rx_done_i,   // byte recibido por UART (no usado en FSM)

    // --- Interfaz LCD (peripheral_top: puertos reales) ---
    output logic        lcd_we_o,         // write enable al registro LCD
    output logic [1:0]  lcd_addr_o,       // direccion del registro LCD
    output logic [31:0] lcd_wdata_o,      // dato a escribir al registro LCD
    input  logic [31:0] lcd_rdata_i,      // lectura de estado LCD (bit 9 = done)

    // --- Buzzer ---
    output logic        play_ok_o,        // reproduce melodia de acierto
    output logic        play_error_o,     // reproduce melodia de error/timeout

    // --- Botones debounced ---
    input  logic        btn_ok,           // iniciar juego / confirmar
    input  logic        btn_scr,          // scroll del LCD (pasado directo a LCD)

    // --- Control ---
    output logic        game_running_o    // activo mientras jugadores responden
);

    // =========================================================================
    // Definicion de estados
    // =========================================================================
    typedef enum logic [3:0] {
        ST_IDLE,      // Espera btn_ok para iniciar juego
        ST_GEN_Q,     // Activa enable_rng, espera ready_question del selector
        ST_SEND_UART, // Activa uart_start_tx_o con la direccion de la pregunta
        ST_WAIT_TX,   // Espera uart_tx_done_i (transmision completa a Python)
        ST_SHOW_LCD,  // Ordena al LCD mostrar la pregunta (start W1P)
        ST_WAIT_LCD,  // Espera bit 9 (done) del registro de estado del LCD
        ST_GAME_RUN,  // Jugadores respondiendo; espera pt o no_answer del datapath
        ST_CHECK,     // Activa buzzer segun resultado de la ronda
        ST_NEXT_RD,   // Verifica si quedan rondas o termino el juego
        ST_END        // Fin del juego; espera btn_ok para reiniciar
    } state_t;

    state_t state, next_state;

    // =========================================================================
    // Registro de estado
    // =========================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) state <= ST_IDLE;
        else     state <= next_state;
    end

    // =========================================================================
    // Logica de siguiente estado y salidas (Moore/Mealy mixta)
    // =========================================================================
    always_comb begin
        // Valores por defecto (sin activar nada)
        next_state       = state;
        enable_rng       = 1'b0;
        uart_start_tx_o  = 1'b0;
        uart_base_addr_o = 32'b0;
        lcd_we_o         = 1'b0;
        lcd_addr_o       = 2'b00;
        lcd_wdata_o      = 32'b0;
        play_ok_o        = 1'b0;
        play_error_o     = 1'b0;
        game_running_o   = 1'b0;

        case (state)

            // -----------------------------------------------------------------
            ST_IDLE: begin
                // Espera btn_ok para arrancar el juego
                if (btn_ok) next_state = ST_GEN_Q;
            end

            // -----------------------------------------------------------------
            ST_GEN_Q: begin
                // Habilita el selector de preguntas hasta que haya una lista
                enable_rng = 1'b1;
                if (ready_question) next_state = ST_SEND_UART;
            end

            // -----------------------------------------------------------------
            ST_SEND_UART: begin
                // Activa un pulso de inicio de transmision UART.
                // uart_base_addr_o[8:5] = question_idx: la ROM usa esos bits
                // como numero de pregunta; bits [4:0] son el offset dentro
                // del mensaje (MSG_LEN = 32 bytes => 5 bits de offset).
                uart_start_tx_o  = 1'b1;
                uart_base_addr_o = {23'b0, question_idx, 5'b0}; // q * 32
                next_state       = ST_WAIT_TX;
            end

            // -----------------------------------------------------------------
            ST_WAIT_TX: begin
                // Espera a que uart_system confirme envio del bloque completo
                if (uart_tx_done_i) next_state = ST_SHOW_LCD;
            end

            // -----------------------------------------------------------------
            ST_SHOW_LCD: begin
                // Escribe al registro 0 del LCD: bit 0 = start W1P, bit 1 = rs=0
                // (comando), bit 3 = home (regresa cursor a posicion 0).
                // El LCD peripheral leera la pregunta del ROM y la mostrara.
                lcd_we_o    = 1'b1;
                lcd_addr_o  = 2'b00;
                lcd_wdata_o = 32'h0000_0009; // bit 3 (home) + bit 0 (start)
                next_state  = ST_WAIT_LCD;
            end

            // -----------------------------------------------------------------
            ST_WAIT_LCD: begin
                // Consulta el bit 9 (done) del registro de estado del LCD.
                // Mientras done=0 se queda en este estado.
                // btn_scr se pasa directamente al LCD desde top_jeopardy
                // sin necesidad de control en la FSM.
                lcd_we_o   = 1'b0;
                lcd_addr_o = 2'b00;
                if (lcd_rdata_i[9]) next_state = ST_GAME_RUN;
            end

            // -----------------------------------------------------------------
            ST_GAME_RUN: begin
                // Cronometro activo; espera senal del datapath:
                //   pt        = alguien respondio (correcto o no)
                //   no_answer = timeout del timer sin que nadie respondiera
                game_running_o = 1'b1;
                if (pt || no_answer) next_state = ST_CHECK;
            end

            // -----------------------------------------------------------------
            ST_CHECK: begin
                // Activa buzzer segun resultado
                play_ok_o    = pt;
                play_error_o = no_answer;
                next_state   = ST_NEXT_RD;
            end

            // -----------------------------------------------------------------
            ST_NEXT_RD: begin
                // Si se completaron 7 preguntas: fin de juego
                // Si no: generar siguiente pregunta
                if (round_done) next_state = ST_END;
                else            next_state = ST_GEN_Q;
            end

            // -----------------------------------------------------------------
            ST_END: begin
                // Juego terminado; btn_ok reinicia (rst hace lo mismo via FF)
                if (btn_ok) next_state = ST_IDLE;
            end

            // -----------------------------------------------------------------
            default: next_state = ST_IDLE;

        endcase
    end

endmodule
