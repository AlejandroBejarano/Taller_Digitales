`timescale 1ns / 1ps
//CAMBIO: se corrigio y completo el modulo top_jeopardy porque el original tenia:
// 1) Instancia "peripheral_controller" (nombre incorrecto; el modulo real es
//    peripheral_top con interfaz UART/LCD separada, no un bus compartido).
// 2) Puerto lcd_en (debe ser lcd_e) y faltaba lcd_rw.
// 3) answer_p1 hardcodeada a 2'b00; debe conectarse al ciclo BTN_SEL (A->B->C->D).
// 4) tB hardcodeado a 1'b0; debe ser uart_rx_done_o del peripheral_top.
// 5) game_controller instanciado con interfaz de bus que no existe en el
//    peripheral_top real.
// 6) Faltaba BTN_SCR para scroll del LCD.
// 7) timer_val_i hardcodeado a 6'd30; se agrego contador regresivo de 1Hz.
// 8) topLFSRandcompany no tenia outputs ready/round_done/question_index/no_answer
//    (ya corregidos en LFSRandcompanytop.sv).

module top_jeopardy (
    input  logic clk,        // 100 MHz de la Basys 3
    input  logic rst,        // Boton central (Reset Maestro)
    input  logic btn_ok,     // Boton arriba (Confirmar/Inicio / Buzzer jugador FPGA)
    input  logic btn_sel,    // Boton izquierda (Cicla respuesta A->B->C->D)
    input  logic btn_scr,    // Boton derecha (Scroll del LCD) - CAMBIO: nuevo

    // UART
    input  logic rx,
    output logic tx,

    // LCD PmodCLP
    output logic lcd_rs,
    output logic lcd_rw,     // CAMBIO: agregado (peripheral_top lo requiere)
    output logic lcd_e,      // CAMBIO: era lcd_en; nombre correcto segun peripheral_top
    output logic [7:0] lcd_d,

    // 7-Segmentos
    output logic [6:0] seg_o,
    output logic [3:0] an_o,
    output logic dp_o,

    // Buzzer
    output logic buzzer_pin
);

    // =========================================================================
    // Senales de reloj y reset debounced
    // =========================================================================
    logic clk_16MHz;
    logic rst_db, ok_db, sel_db, scr_db;

    // IP: Clocking Wizard configurado a 16MHz desde 100MHz
    clk_wiz_0 clk_inst (
        .clk_out1(clk_16MHz),
        .reset   (rst),
        .locked  (),
        .clk_in1 (clk)
    );

    // Debouncers para botones fisicos
    debouncer db_rst (.clk(clk_16MHz), .reset(1'b0),   .btn_in(rst),     .btn_out(rst_db));
    debouncer db_ok  (.clk(clk_16MHz), .reset(rst_db), .btn_in(btn_ok),  .btn_out(ok_db));
    debouncer db_sel (.clk(clk_16MHz), .reset(rst_db), .btn_in(btn_sel), .btn_out(sel_db));
    debouncer db_scr (.clk(clk_16MHz), .reset(rst_db), .btn_in(btn_scr), .btn_out(scr_db));

    // =========================================================================
    // Detector de flanco ascendente para sel_db (BTN_SEL -> ciclo de respuesta)
    // =========================================================================
    logic sel_db_prev;
    logic sel_edge;

    always_ff @(posedge clk_16MHz or posedge rst_db) begin
        if (rst_db) sel_db_prev <= 1'b0;
        else        sel_db_prev <= sel_db;
    end

    assign sel_edge = sel_db & ~sel_db_prev;

    // =========================================================================
    // Registro de respuesta del jugador FPGA (BTN_SEL cicla A->B->C->D)
    // 00=A  01=B  10=C  11=D (mismo encoding que answer_table en answerChecker)
    // =========================================================================
    logic [1:0] fpga_answer;

    always_ff @(posedge clk_16MHz or posedge rst_db) begin
        if (rst_db)     fpga_answer <= 2'b00;
        else if (sel_edge) fpga_answer <= fpga_answer + 2'b01; // 00->01->10->11->00
    end

    // =========================================================================
    // Senales internas de juego
    // =========================================================================
    logic [3:0] q_idx;           // indice de pregunta activa
    logic       ready_q;         // question_selector: pregunta lista
    logic       round_done;      // 7 preguntas completadas
    logic       en_rng;          // habilita generador de preguntas
    logic       pt;              // punto asignado en esta ronda
    logic       no_answer_pulse; // nadie respondio a tiempo
    logic [3:0] scoreA, scoreB;
    logic       playerA_first_w, playerB_first_w, both_first_w;

    // Timer y contador regresivo para display
    logic        rst_i_30s;      // pulso cada 30 segundos (del timer)
    logic [5:0]  timer_display;  // valor a mostrar en 7-seg (segundos restantes)
    logic        game_run;       // game_controller indica que jugadores estan respondiendo

    // Interfaz UART (game_controller <-> peripheral_top)
    logic        uart_start_tx;
    logic [31:0] uart_base_addr;
    logic        uart_tx_done;
    logic        uart_rx_done;
    logic [7:0]  uart_rx_data;

    // Interfaz LCD (game_controller <-> peripheral_top)
    logic        lcd_we;
    logic [1:0]  lcd_addr;
    logic [31:0] lcd_wdata;
    logic [31:0] lcd_rdata;

    // Buzzer (game_controller -> peripheral_top)
    logic        play_ok;
    logic        play_error;

    // =========================================================================
    // 1. Timer de 30 segundos
    // =========================================================================
    timer #( .CNT_MAX(479_999_999) ) main_timer (  // 30s @ 16MHz
        .clk  (clk_16MHz),
        .rst  (rst_db),
        .rst_i(rst_i_30s)
    );

    // =========================================================================
    // 2. Contador regresivo para display de 7 segmentos (1 pulso/segundo)
    //    Se recarga en 30 cuando empieza un nuevo turno de respuesta (game_run)
    // =========================================================================
    localparam int CNT_1SEC = 16_000_000 - 1; // 1 segundo @ 16MHz
    logic [23:0] sec_ctr;
    logic        tick_1s;
    logic        game_run_prev;

    always_ff @(posedge clk_16MHz or posedge rst_db) begin
        if (rst_db || !game_run) begin
            sec_ctr  <= 24'd0;
            tick_1s  <= 1'b0;
        end else if (sec_ctr == CNT_1SEC) begin
            sec_ctr  <= 24'd0;
            tick_1s  <= 1'b1;
        end else begin
            sec_ctr  <= sec_ctr + 24'd1;
            tick_1s  <= 1'b0;
        end
    end

    always_ff @(posedge clk_16MHz or posedge rst_db) begin
        if (rst_db) begin
            timer_display  <= 6'd30;
            game_run_prev  <= 1'b0;
        end else begin
            game_run_prev <= game_run;
            // Recargar al inicio de cada turno de respuesta
            if (game_run && !game_run_prev)
                timer_display <= 6'd30;
            // Decrementar un segundo a la vez mientras esta corriendo
            else if (tick_1s && timer_display > 6'd0)
                timer_display <= timer_display - 6'd1;
        end
    end

    // =========================================================================
    // 3. Unidad de control (game_controller)
    // =========================================================================
    game_controller master_fsm (
        .clk            (clk_16MHz),
        .rst            (rst_db),
        // Datapath
        .ready_question (ready_q),
        .question_idx   (q_idx),
        .enable_rng     (en_rng),
        .round_done     (round_done),
        .pt             (pt),
        .no_answer      (no_answer_pulse),
        // UART
        .uart_start_tx_o(uart_start_tx),
        .uart_base_addr_o(uart_base_addr),
        .uart_tx_done_i  (uart_tx_done),
        .uart_rx_done_i  (uart_rx_done),
        // LCD
        .lcd_we_o       (lcd_we),
        .lcd_addr_o     (lcd_addr),
        .lcd_wdata_o    (lcd_wdata),
        .lcd_rdata_i    (lcd_rdata),
        // Buzzer
        .play_ok_o      (play_ok),
        .play_error_o   (play_error),
        // Botones
        .btn_ok         (ok_db),
        .btn_scr        (scr_db),
        // Control
        .game_running_o (game_run)
    );

    // =========================================================================
    // 4. Datapath del juego (topLFSRandcompany)
    // =========================================================================
    topLFSRandcompany datapath (
        .clk           (clk_16MHz),
        .rst           (rst_db),
        .rst_i         (rst_i_30s),       // pulso de nueva ronda (30s timer)
        .enable        (en_rng),
        .i_Seed_Data   (4'b1011),         // semilla LFSR fija
        .answer_p1     (fpga_answer),     // respuesta jugador FPGA (BTN_SEL)
        .answer_p2     (uart_rx_data[1:0]),// respuesta jugador PC (UART RX byte)
        .tA            (ok_db),           // buzzer jugador FPGA (BTN_OK)
        .tB            (uart_rx_done),    // buzzer jugador PC (dato recibido por UART)
        // Outputs de estado
        .pt            (pt),
        .playerA_first (playerA_first_w),
        .playerB_first (playerB_first_w),
        .both_first    (both_first_w),
        .scoreA        (scoreA),
        .scoreB        (scoreB),
        // Outputs para game_controller
        .ready         (ready_q),
        .round_done    (round_done),
        .question_index(q_idx),
        .no_answer     (no_answer_pulse)
    );

    // =========================================================================
    // 5. Controlador de perifericos (peripheral_top)
    //    CAMBIO: era instanciado como peripheral_controller con bus compartido;
    //    el modulo real se llama peripheral_top con UART y LCD separados.
    //    CAMBIO: lcd_en -> lcd_e, se agrego lcd_rw.
    // =========================================================================
    peripheral_top #(
        .MSG_LEN (32),
        .SIM_FAST(0)
    ) u_peripherals (
        .clk_i          (clk_16MHz),
        .rst_i          (rst_db),
        // UART
        .uart_start_tx_i(uart_start_tx),
        .uart_base_addr_i(uart_base_addr),
        .uart_tx_done_o (uart_tx_done),
        .uart_rx_done_o (uart_rx_done),
        .uart_rx_data_o (uart_rx_data),
        // LCD
        .lcd_we_i       (lcd_we),
        .lcd_addr_i     (lcd_addr),
        .lcd_wdata_i    (lcd_wdata),
        .lcd_rdata_o    (lcd_rdata),
        .lcd_option_byte_o(), // no se usa en este nivel
        // Segmentos
        .timer_i        (timer_display),  // contador regresivo 30->0
        .score_fpga_i   (scoreA),
        .score_pc_i     (scoreB),
        // Buzzer
        .play_ok_i      (play_ok),
        .play_error_i   (play_error),
        // Pines fisicos
        .rx             (rx),
        .tx             (tx),
        .lcd_rs         (lcd_rs),
        .lcd_rw         (lcd_rw),
        .lcd_e          (lcd_e),
        .lcd_d          (lcd_d),
        .seg_o          (seg_o),
        .an_o           (an_o),
        .dp_o           (dp_o),
        .buzzer_pin     (buzzer_pin)
    );

endmodule