// =============================================================================
// peripheral_top.sv - Módulo Integrador de Periféricos (UART, LCD, 7-Seg, Buzzer)
//
// Responsabilidades:
//   - Comparte las ROMs duales (preguntas y respuestas) entre subsistema UART y LCD.
//   - Subsistema UART para el jugador PC:
//       · uart_tx_fsm:      envía la pregunta y opciones por UART (SOH/STX/ETX).
//       · answer_checker:   detecta y valida la respuesta A/B/C/D del PC.
//       · result_sender:    envía el resultado (ENQ) y el marcador (ACK) al PC.
//   - Subsistema LCD para el jugador FPGA:
//       · lcd_fsm:          despliega pregunta / opciones y captura la selección.
//       · Checker combinacional: verifica si la opción elegida es correcta.
//   - Hardware auxiliar:
//       · segments:         muestra timer, scoreA y scoreB en displays 7-seg.
//       · buzzer:           genera tonos de OK / ERROR.
//
// Entradas desde CU_top:
//   enable_lcd_i   – Pulso 1 ciclo: iniciar nueva pregunta en LCD.
//   enable_uart_i  – Pulso 1 ciclo: iniciar transmisión de pregunta por UART.
//   question_idx_i – Índice (0-9) de la pregunta activa.
//   timer_val_i    – Valor del temporizador para mostrarlo en 7-segmentos.
//   scoreA_i       – Puntaje jugador FPGA.
//   scoreB_i       – Puntaje jugador PC.
//   play_ok_i      – Pulso: respuesta correcta → buzzer tono OK.
//   play_error_i   – Pulso: respuesta incorrecta / timeout → buzzer tono ERROR.
//   round_over_i   – Pulso de CU_top: la ronda terminó; señal para result_sender.
//
// Salidas hacia CU_top:
//   fpga_ans_valid_o  – Pulso: el jugador FPGA confirmó su opción (btn_ok en LCD).
//   fpga_ans_correct_o– Nivel: la opción del FPGA coincide con la respuesta correcta.
//   pc_ans_valid_o    – Pulso: el jugador PC envió un byte A/B/C/D por UART.
//   pc_ans_correct_o  – Nivel: la respuesta del PC es correcta.
// =============================================================================
`timescale 1ns / 1ps

module peripheral_top (
    input  logic        clk_16MHz,
    input  logic        rst,

    // Comandos desde CU_top
    input  logic        enable_lcd_i,
    input  logic        enable_uart_i,
    input  logic [3:0]  question_idx_i,

    input  logic [5:0]  timer_val_i,
    input  logic [3:0]  scoreA_i,
    input  logic [3:0]  scoreB_i,

    input  logic        play_ok_i,
    input  logic        play_error_i,
    input  logic        round_over_i,   // Pulso de CU_top: la ronda terminó

    // Botones jugador FPGA (Scroll y Seleccionar Opcion/Cursor)
    input  logic        btn_scr_i,
    input  logic        btn_sel_i,
    input  logic        btn_ok_i,

    // Resultados devueltos hacia CU_top
    output logic        fpga_ans_valid_o,
    output logic        fpga_ans_correct_o,
    output logic        pc_ans_valid_o,
    output logic        pc_ans_correct_o,

    // Pines Físicos
    input  logic        rx,
    output logic        tx,
    output logic        lcd_rs,
    output logic        lcd_rw,
    output logic        lcd_e,
    output logic [7:0]  lcd_d,
    output logic [6:0]  seg,
    output logic [3:0]  an,
    output logic        dp,
    output logic        buzzer_pin
);

    // =========================================================================
    // Block RAMs (ROM Preguntas y Opciones) configuradas a Dual-Port
    // Puerto A → subsistema UART (uart_tx_fsm + answer_checker)
    // Puerto B → subsistema LCD  (lcd_fsm)
    // =========================================================================
    logic [8:0] rom_q_addr_uart, rom_q_addr_lcd;
    logic [7:0] rom_q_data_uart, rom_q_data_lcd;

    blk_mem_gen_0 rom_preguntas (
        .clka (clk_16MHz),    .ena (1'b1),
        .addra(rom_q_addr_uart), .douta(rom_q_data_uart),

        .clkb (clk_16MHz),    .enb (1'b1),
        .addrb(rom_q_addr_lcd),  .doutb(rom_q_data_lcd)
    );

    logic [8:0] rom_a_addr_uart, rom_a_addr_lcd;
    logic [7:0] rom_a_data_uart, rom_a_data_lcd;

    blk_mem_gen_1 rom_respuestas (
        .clka (clk_16MHz),    .ena (1'b1),
        .addra(rom_a_addr_uart), .douta(rom_a_data_uart),

        .clkb (clk_16MHz),    .enb (1'b1),
        .addrb(rom_a_addr_lcd),  .doutb(rom_a_data_lcd)
    );

    // =========================================================================
    // UART Subsystem (Jugador PC)
    // Bus compartido entre uart_tx_fsm, answer_checker y result_sender.
    // =========================================================================
    // uart_we / uart_addr / uart_wdata – señales de escritura hacia uart_interface
    // uart_rdata – lectura compartida de registros UART (control, RX)
    logic        uart_we;
    logic [1:0]  uart_addr;
    logic [31:0] uart_wdata;
    logic [31:0] uart_rdata;

    uart_interface u_uart (
        .clk_i(clk_16MHz), .rst_i(rst),
        .we_i(uart_we), .addr_i(uart_addr), .wdata_i(uart_wdata), .rdata_o(uart_rdata),
        .rx(rx), .tx(tx)
    );

    // tx_fsm_we/addr/wdata – bus generado por uart_tx_fsm cuando está transmitiendo
    logic        tx_fsm_we;
    logic [1:0]  tx_fsm_addr;
    logic [31:0] tx_fsm_wdata;

    uart_tx_fsm u_uart_tx_fsm (
        .clk_i        (clk_16MHz),
        .rst_i        (rst),
        .start_i      (enable_uart_i),      // Pulso de CU_top: enviar pregunta
        .question_idx_i(question_idx_i),    // Índice de pregunta a transmitir
        .done_o       (),
        .busy_o       (),
        .rom_q_addr_o (rom_q_addr_uart),
        .rom_q_data_i (rom_q_data_uart),
        .rom_a_addr_o (rom_a_addr_uart),
        .rom_a_data_i (rom_a_data_uart),
        .uart_we_o    (tx_fsm_we),
        .uart_addr_o  (tx_fsm_addr),
        .uart_wdata_o (tx_fsm_wdata),
        .uart_rdata_i (uart_rdata)
    );

    // chk_we/addr/wdata – bus generado por answer_checker al leer/limpiar RX
    logic        chk_we;
    logic [1:0]  chk_addr;
    logic [31:0] chk_wdata;

    answer_checker u_checker_pc (
        .clk_i            (clk_16MHz),
        .rst_i            (rst),
        .enable_i         (1'b1),           // Siempre activo para detectar respuesta PC
        .question_idx_i   (question_idx_i),
        .answer_valid_o   (pc_ans_valid_o),    // Pulso: byte válido A/B/C/D recibido
        .answer_correct_o (pc_ans_correct_o),  // Nivel: la respuesta es correcta
        .answer_letter_o  (),
        .answer_invalid_o (),
        .uart_we_o        (chk_we),
        .uart_addr_o      (chk_addr),
        .uart_wdata_o     (chk_wdata),
        .uart_rdata_i     (uart_rdata)
    );

    // =========================================================================
    // Result Sender: Envía ENQ+ACK al jugador PC tras cada ronda
    // =========================================================================
    // rs_send_result  – pulso: enviar ENQ con resultado de la ronda
    // rs_result_correct – nivel: indica si la respuesta del PC fue correcta
    // rs_send_score   – pulso: enviar ACK con puntajes actualizados
    // rs_done         – pulso de 1 ciclo: transmisión completada
    // rs_busy         – nivel: result_sender está transmitiendo
    logic        rs_send_result;
    logic        rs_result_correct;
    logic        rs_send_score;
    logic        rs_done;
    logic        rs_busy;
    logic        rs_uart_we;
    logic [1:0]  rs_uart_addr;
    logic [31:0] rs_uart_wdata;

    result_sender u_result_sender (
        .clk_i            (clk_16MHz),
        .rst_i            (rst),
        .send_result_i    (rs_send_result),
        .result_correct_i (rs_result_correct),
        .send_score_i     (rs_send_score),
        .score_pc_i       ({4'b0, scoreB_i}),   // scoreB = jugador PC
        .score_fpga_i     ({4'b0, scoreA_i}),   // scoreA = jugador FPGA
        .send_gameover_i  (1'b0),
        .done_o           (rs_done),
        .busy_o           (rs_busy),
        .uart_we_o        (rs_uart_we),
        .uart_addr_o      (rs_uart_addr),
        .uart_wdata_o     (rs_uart_wdata),
        .uart_rdata_i     (uart_rdata)
    );

    // =========================================================================
    // FSM de Gestión de Resultado (RM): controla cuándo enviar ENQ+ACK al PC
    //
    // La FSM se activa con enable_uart_i (inicio de ronda) y espera hasta que:
    //   a) El PC responde (pc_ans_valid_o) → latcha resultado e inicia envío.
    //   b) La ronda termina sin respuesta del PC (round_over_i) → envía ENQ(0).
    //
    // Estados:
    //   RM_IDLE     – espera enable_uart_i para iniciar monitoreo de la ronda.
    //   RM_WAIT_ANS – espera pc_ans_valid_o o round_over_i.
    //   RM_SEND_RES – pulsa rs_send_result para enviar ENQ.
    //   RM_WAIT_RES – espera rs_done (ENQ completado).
    //   RM_SEND_SCR – pulsa rs_send_score para enviar ACK (score ya actualizado).
    //   RM_WAIT_SCR – espera rs_done (ACK completado) → vuelve a RM_IDLE.
    // =========================================================================
    typedef enum logic [2:0] {
        RM_IDLE,
        RM_WAIT_ANS,
        RM_SEND_RES,
        RM_WAIT_RES,
        RM_SEND_SCR,
        RM_WAIT_SCR
    } rm_state_t;

    rm_state_t rm_state;
    logic      rm_pc_answered;    // Flag: PC ya respondió esta ronda (evita doble envío)
    logic      rm_ans_correct;    // Resultado latched de la respuesta del PC

    always_ff @(posedge clk_16MHz) begin
        if (rst) begin
            rm_state          <= RM_IDLE;
            rm_pc_answered    <= 1'b0;
            rm_ans_correct    <= 1'b0;
            rs_send_result    <= 1'b0;
            rs_result_correct <= 1'b0;
            rs_send_score     <= 1'b0;
        end else begin
            // Defaults: pulsos de 1 ciclo
            rs_send_result <= 1'b0;
            rs_send_score  <= 1'b0;

            case (rm_state)

                // Esperar el pulso de inicio de ronda
                RM_IDLE: begin
                    rm_pc_answered <= 1'b0;
                    if (enable_uart_i)
                        rm_state <= RM_WAIT_ANS;
                end

                // Esperar respuesta del PC o fin de ronda
                RM_WAIT_ANS: begin
                    if (pc_ans_valid_o && !rm_pc_answered) begin
                        // PC respondió: latchar resultado y preparar envío
                        rm_pc_answered <= 1'b1;
                        rm_ans_correct <= pc_ans_correct_o;
                        rm_state       <= RM_SEND_RES;
                    end else if (round_over_i && !rm_pc_answered) begin
                        // La ronda terminó sin que el PC respondiera (timer o FPGA ganó)
                        rm_ans_correct <= 1'b0;
                        rm_state       <= RM_SEND_RES;
                    end
                end

                // Lanzar envío de ENQ (resultado de la ronda al PC)
                RM_SEND_RES: begin
                    if (!rs_busy) begin
                        rs_result_correct <= rm_ans_correct;
                        rs_send_result    <= 1'b1;
                        rm_state          <= RM_WAIT_RES;
                    end
                end

                // Esperar que se complete el envío del ENQ
                RM_WAIT_RES: begin
                    if (rs_done)
                        rm_state <= RM_SEND_SCR;
                end

                // Lanzar envío de ACK (score actualizado al PC)
                // En este punto CU_top ya actualizó scoreA_o/scoreB_o (centenares de ciclos después)
                RM_SEND_SCR: begin
                    if (!rs_busy) begin
                        rs_send_score <= 1'b1;
                        rm_state      <= RM_WAIT_SCR;
                    end
                end

                // Esperar que se complete el envío del ACK
                RM_WAIT_SCR: begin
                    if (rs_done)
                        rm_state <= RM_IDLE;
                end

                default: rm_state <= RM_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Mux UART: tx_fsm > result_sender > answer_checker
    // Prioridad: transmisión de pregunta > envío de resultado > lectura de RX
    // =========================================================================
    always_comb begin
        if (tx_fsm_we) begin
            uart_we    = tx_fsm_we;
            uart_addr  = tx_fsm_addr;
            uart_wdata = tx_fsm_wdata;
        end else if (rs_uart_we) begin
            uart_we    = rs_uart_we;
            uart_addr  = rs_uart_addr;
            uart_wdata = rs_uart_wdata;
        end else begin
            uart_we    = chk_we;
            uart_addr  = chk_addr;
            uart_wdata = chk_wdata;
        end
    end

    // =========================================================================
    // LCD Subsystem (Jugador FPGA)
    // lcd_peripheral es el controlador hardware; lcd_fsm genera los comandos.
    // =========================================================================
    // lcd_we/addr/wdata – bus de comandos generado por lcd_fsm
    // lcd_rdata         – estado del LCD (bit 9 = done, bit 8 = busy)
    logic        lcd_we;
    logic [1:0]  lcd_addr;
    logic [31:0] lcd_wdata;
    logic [31:0] lcd_rdata;

    lcd_peripheral u_lcd (
        .clk_i          (clk_16MHz),
        .rst_i          (rst),
        .write_enable_i (lcd_we),
        .addr_i         (lcd_addr),
        .wdata_i        (lcd_wdata),
        .rdata_o        (lcd_rdata),
        .lcd_rs_o       (lcd_rs),
        .lcd_rw_o       (lcd_rw),
        .lcd_en_o       (lcd_e),
        .lcd_data_o     (lcd_d)
    );

    // lcd_fpga_char – letra ASCII (A/B/C/D) seleccionada actualmente por el FPGA
    logic [7:0] lcd_fpga_char;

    lcd_fsm u_lcd_fsm (
        .clk_i               (clk_16MHz),
        .rst_i               (rst),
        .enable_i            (enable_lcd_i),      // Pulso: cargar nueva pregunta
        .question_idx_i      (question_idx_i),
        .btn_scr_i           (btn_scr_i),         // Alternar vista pregunta/opciones
        .btn_sel_i           (btn_sel_i),         // Mover cursor A→B→C→D
        .btn_ok_i            (btn_ok_i),          // Confirmar selección
        .fpga_answer_valid_o (fpga_ans_valid_o),  // Pulso: FPGA confirmó respuesta
        .fpga_answer_char_o  (lcd_fpga_char),     // Letra elegida por FPGA
        .rom_q_addr_o        (rom_q_addr_lcd),
        .rom_q_data_i        (rom_q_data_lcd),
        .rom_a_addr_o        (rom_a_addr_lcd),
        .rom_a_data_i        (rom_a_data_lcd),
        .lcd_we_o            (lcd_we),
        .lcd_addr_o          (lcd_addr),
        .lcd_wdata_o         (lcd_wdata),
        .lcd_rdata_i         (lcd_rdata)
    );

    // =========================================================================
    // Checker de respuesta FPGA (Combinacional)
    // Compara la letra elegida en LCD con la respuesta correcta en la LUT.
    // =========================================================================
    function automatic logic [7:0] get_correct_answer(input logic [3:0] idx);
        case (idx)
            4'd0:    get_correct_answer = 8'h43; // C
            4'd1:    get_correct_answer = 8'h42; // B
            4'd2:    get_correct_answer = 8'h41; // A
            4'd3:    get_correct_answer = 8'h41; // A
            4'd4:    get_correct_answer = 8'h43; // C
            4'd5:    get_correct_answer = 8'h42; // B
            4'd6:    get_correct_answer = 8'h42; // B
            4'd7:    get_correct_answer = 8'h44; // D
            4'd8:    get_correct_answer = 8'h44; // D
            4'd9:    get_correct_answer = 8'h41; // A
            default: get_correct_answer = 8'h00; // Inválido
        endcase
    endfunction

    assign fpga_ans_correct_o = (lcd_fpga_char == get_correct_answer(question_idx_i));

    // =========================================================================
    // Hardware Auxiliar Visual/Sonoro
    // =========================================================================
    // segments: muestra timer (izquierda), scoreA y scoreB en displays 7-seg
    // buzzer:   genera tonos OK (play_ok_i) o ERROR (play_error_i)
    segments u_segments (
        .clk_i       (clk_16MHz),
        .rst_i       (rst),
        .timer_i     (timer_val_i),
        .score_fpga_i(scoreA_i),
        .score_pc_i  (scoreB_i),
        .seg_o       (seg),
        .an_o        (an),
        .dp_o        (dp)
    );

    buzzer u_buzzer (
        .clk_i      (clk_16MHz),
        .rst_i      (rst),
        .play_ok_i  (play_ok_i),
        .play_err_i (play_error_i),
        .buzzer_o   (buzzer_pin)
    );

endmodule
