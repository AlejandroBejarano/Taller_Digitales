// =============================================================================
// uart_game_top.sv - Top-level del subsistema UART para Jeopardy
//
// Integra todos los módulos UART del juego:
//   - PLL (clk_wiz_0): 100 MHz → 16 MHz
//   - uart_interface: periférico UART con interfaz estándar de 32 bits
//   - ROMs: blk_mem_gen_0 (preguntas), blk_mem_gen_1 (respuestas)
//   - uart_tx_fsm: transmisión de preguntas/opciones
//   - answer_checker: validación de respuestas del jugador PC
//   - result_sender: envío de feedback (resultado, score, game over)
//   - FSM maestra: controla el flujo del juego para la parte UART
//   - MUX de bus: arbitra acceso al bus UART entre los submódulos
//
// Señales externas:
//   - clk_100MHz: reloj del sistema (pin W5 de Basys3)
//   - rst_i: reset (botón central BTNC)
//   - btn_start_i: iniciar ronda (botón arriba BTNU)
//   - rx, tx: líneas UART
//   - led[3:0]: LEDs de diagnóstico
// =============================================================================
`timescale 1ns / 1ps

module uart_game_top (
    input  logic        clk_100MHz,    // Pin W5 (100 MHz)
    input  logic        rst_i,         // BTNC: Reset activo alto
    input  logic        btn_start_i,   // BTNU: Iniciar ronda
    input  logic        rx,            // Línea RX UART
    output logic        tx,            // Línea TX UART
    output logic [3:0]  led            // LEDs de diagnóstico
);

    // =========================================================================
    // PLL: 100 MHz → 16 MHz
    // =========================================================================
    logic clk_16MHz;
    logic locked;

    clk_wiz_0 pll_inst (
        .clk_in1  (clk_100MHz),
        .clk_out1 (clk_16MHz),
        .reset    (rst_i),
        .locked   (locked)
    );

    // =========================================================================
    // Reset sincronizado al dominio de 16 MHz (doble FF anti-metaestabilidad)
    // =========================================================================
    logic rst_meta, rst_sync, rst_sys;

    always_ff @(posedge clk_16MHz) begin
        rst_meta <= rst_i | ~locked;
        rst_sync <= rst_meta;
        rst_sys  <= rst_sync;
    end

    // =========================================================================
    // Sincronizador de botón start (doble FF + detección de flanco)
    // =========================================================================
    logic btn_s1, btn_s2, btn_s3, btn_start_pulse;

    always_ff @(posedge clk_16MHz) begin
        if (rst_sys) begin
            btn_s1 <= 1'b0; btn_s2 <= 1'b0; btn_s3 <= 1'b0;
            btn_start_pulse <= 1'b0;
        end else begin
            btn_s1 <= btn_start_i;
            btn_s2 <= btn_s1;
            btn_s3 <= btn_s2;
            btn_start_pulse <= btn_s2 & ~btn_s3; // Flanco de subida
        end
    end

    // =========================================================================
    // Bus UART: señales hacia uart_interface
    // =========================================================================
    logic        uart_we;
    logic [1:0]  uart_addr;
    logic [31:0] uart_wdata;
    logic [31:0] uart_rdata;

    uart_interface uart_if (
        .clk_i   (clk_16MHz),
        .rst_i   (rst_sys),
        .we_i    (uart_we),
        .addr_i  (uart_addr),
        .wdata_i (uart_wdata),
        .rdata_o (uart_rdata),
        .rx      (rx),
        .tx      (tx)
    );

    // =========================================================================
    // ROMs de preguntas y respuestas (Block Memory Generator IPs de Vivado)
    // Configuración: Single Port ROM, 8 bits de ancho, 320 de profundidad
    //
    // NOTA: Debes crear estas IPs en Vivado:
    //   - blk_mem_gen_0: ROM de preguntas, cargada con preguntas.coe
    //   - blk_mem_gen_1: ROM de respuestas, cargada con respuestas.coe
    // =========================================================================
    logic [8:0] rom_q_addr;
    logic [7:0] rom_q_data;
    logic [8:0] rom_a_addr;
    logic [7:0] rom_a_data;

    blk_mem_gen_0 rom_preguntas (
        .clka  (clk_16MHz),
        .ena   (1'b1),
        .addra (rom_q_addr),
        .douta (rom_q_data)
    );

    blk_mem_gen_1 rom_respuestas (
        .clka  (clk_16MHz),
        .ena   (1'b1),
        .addra (rom_a_addr),
        .douta (rom_a_data)
    );

    // =========================================================================
    // Registros del juego (declarados aquí porque result_sender los necesita)
    // =========================================================================
    logic [3:0] question_idx;        // Índice de pregunta actual (0-9)
    logic [2:0] round_count;         // Contador de rondas (0-6, 7 rondas)
    logic [7:0] score_pc;            // Puntaje jugador PC
    logic [7:0] score_fpga;          // Puntaje jugador FPGA (por ahora solo PC)
    logic       last_answer_correct; // Resultado de la última respuesta

    // =========================================================================
    // Señales de los submódulos
    // =========================================================================

    // --- uart_tx_fsm ---
    logic        txfsm_start;
    logic [3:0]  txfsm_q_idx;
    logic        txfsm_done;
    logic        txfsm_busy;
    logic        txfsm_uart_we;
    logic [1:0]  txfsm_uart_addr;
    logic [31:0] txfsm_uart_wdata;

    // --- answer_checker ---
    logic        ac_enable;
    logic        ac_answer_valid;
    logic        ac_answer_correct;
    logic [7:0]  ac_answer_letter;
    logic        ac_answer_invalid;
    logic        ac_uart_we;
    logic [1:0]  ac_uart_addr;
    logic [31:0] ac_uart_wdata;

    // --- result_sender ---
    logic        rs_send_result;
    logic        rs_result_correct;
    logic        rs_send_score;
    logic        rs_send_gameover;
    logic        rs_done;
    logic        rs_busy;
    logic        rs_uart_we;
    logic [1:0]  rs_uart_addr;
    logic [31:0] rs_uart_wdata;

    // =========================================================================
    // Instancias de submódulos
    // =========================================================================

    uart_tx_fsm u_tx_fsm (
        .clk_i          (clk_16MHz),
        .rst_i          (rst_sys),
        .start_i        (txfsm_start),
        .question_idx_i (txfsm_q_idx),
        .done_o         (txfsm_done),
        .busy_o         (txfsm_busy),
        .rom_q_addr_o   (rom_q_addr),
        .rom_q_data_i   (rom_q_data),
        .rom_a_addr_o   (rom_a_addr),
        .rom_a_data_i   (rom_a_data),
        .uart_we_o      (txfsm_uart_we),
        .uart_addr_o    (txfsm_uart_addr),
        .uart_wdata_o   (txfsm_uart_wdata),
        .uart_rdata_i   (uart_rdata)
    );

    answer_checker u_ans_check (
        .clk_i          (clk_16MHz),
        .rst_i          (rst_sys),
        .enable_i       (ac_enable),
        .question_idx_i (txfsm_q_idx),
        .answer_valid_o (ac_answer_valid),
        .answer_correct_o(ac_answer_correct),
        .answer_letter_o(ac_answer_letter),
        .answer_invalid_o(ac_answer_invalid),
        .uart_we_o      (ac_uart_we),
        .uart_addr_o    (ac_uart_addr),
        .uart_wdata_o   (ac_uart_wdata),
        .uart_rdata_i   (uart_rdata)
    );

    result_sender u_res_send (
        .clk_i           (clk_16MHz),
        .rst_i           (rst_sys),
        .send_result_i   (rs_send_result),
        .result_correct_i(rs_result_correct),
        .send_score_i    (rs_send_score),
        .score_pc_i      (score_pc),
        .score_fpga_i    (score_fpga),
        .send_gameover_i (rs_send_gameover),
        .done_o          (rs_done),
        .busy_o          (rs_busy),
        .uart_we_o       (rs_uart_we),
        .uart_addr_o     (rs_uart_addr),
        .uart_wdata_o    (rs_uart_wdata),
        .uart_rdata_i    (uart_rdata)
    );

    // =========================================================================
    // MUX de bus UART
    // El bus UART se comparte entre uart_tx_fsm, answer_checker y result_sender.
    // Solo uno puede tener acceso a la vez, controlado por la FSM maestra.
    // =========================================================================
    logic [1:0] bus_owner;
    localparam [1:0] BUS_IDLE      = 2'd0;
    localparam [1:0] BUS_TX_FSM    = 2'd1;
    localparam [1:0] BUS_ANS_CHECK = 2'd2;
    localparam [1:0] BUS_RES_SEND  = 2'd3;

    always_comb begin
        case (bus_owner)
            BUS_TX_FSM: begin
                uart_we    = txfsm_uart_we;
                uart_addr  = txfsm_uart_addr;
                uart_wdata = txfsm_uart_wdata;
            end
            BUS_ANS_CHECK: begin
                uart_we    = ac_uart_we;
                uart_addr  = ac_uart_addr;
                uart_wdata = ac_uart_wdata;
            end
            BUS_RES_SEND: begin
                uart_we    = rs_uart_we;
                uart_addr  = rs_uart_addr;
                uart_wdata = rs_uart_wdata;
            end
            default: begin
                uart_we    = 1'b0;
                uart_addr  = 2'b00;
                uart_wdata = 32'b0;
            end
        endcase
    end

    // =========================================================================
    // FSM maestra del juego (simplificada para subsistema UART)
    // =========================================================================
    typedef enum logic [3:0] {
        G_IDLE,                // Esperar botón de inicio
        G_SELECT_QUESTION,     // Seleccionar pregunta pseudoaleatoria
        G_SEND_QUESTION,       // Transmitir pregunta + opciones por UART
        G_WAIT_TX_DONE,        // Esperar que uart_tx_fsm termine
        G_WAIT_ANSWER,         // Esperar respuesta del jugador PC
        G_PROCESS_ANSWER,      // Procesar resultado
        G_SEND_RESULT,         // Enviar resultado por UART
        G_WAIT_RESULT_DONE,    // Esperar que result_sender termine
        G_SEND_SCORE,          // Enviar score por UART
        G_WAIT_SCORE_DONE,     // Esperar que score se envíe
        G_NEXT_ROUND,          // Preparar siguiente ronda
        G_GAME_OVER,           // Enviar fin de partida
        G_WAIT_GAMEOVER_DONE   // Esperar que game over se envíe
    } game_state_t;

    game_state_t game_state;

    // LFSR para selección pseudoaleatoria de preguntas
    logic [3:0] lfsr;
    logic [9:0] question_used;       // Bitmap: 1 = pregunta ya usada
    logic [3:0] selected_question;   // Pregunta seleccionada (registro)

    // LFSR de 4 bits: polinomio x^4 + x + 1 (período 15)
    always_ff @(posedge clk_16MHz) begin
        if (rst_sys) begin
            lfsr <= 4'b1010; // Semilla inicial (no debe ser 0)
        end else begin
            lfsr <= {lfsr[2:0], lfsr[3] ^ lfsr[0]};
        end
    end

    // =========================================================================
    // Función sintetizable: encontrar pregunta no usada
    // Recorre circularmente las 10 preguntas desde un valor semilla.
    // Evita el operador % usando comparación explícita para wrapping.
    // =========================================================================
    function automatic logic [3:0] find_unused_question(
        input logic [3:0] seed,
        input logic [9:0] used
    );
        logic [4:0] raw;       // 5 bits para sumas hasta 24
        logic [3:0] candidate;
        find_unused_question = 4'd0; // default: pregunta 0
        for (int i = 0; i < 10; i++) begin
            // Calcular (seed + i) mod 10 sin operador %
            // seed puede ser 0-15, i puede ser 0-9, raw máximo = 24
            raw = {1'b0, seed} + i[4:0];
            if (raw >= 5'd20)
                raw = raw - 5'd20;
            else if (raw >= 5'd10)
                raw = raw - 5'd10;
            candidate = raw[3:0];
            if (!used[candidate]) begin
                find_unused_question = candidate;
                return;
            end
        end
    endfunction

    // =========================================================================
    // Lógica auxiliar para marcar pregunta como usada
    // (evitar asignación con índice variable en always_ff)
    // =========================================================================
    logic [9:0] question_used_next;

    always_comb begin
        question_used_next = question_used;
        question_used_next[selected_question] = 1'b1;
    end

    // =========================================================================
    // FSM maestra secuencial
    // =========================================================================
    always_ff @(posedge clk_16MHz) begin
        if (rst_sys) begin
            game_state          <= G_IDLE;
            question_idx        <= 4'd0;
            round_count         <= 3'd0;
            score_pc            <= 8'd0;
            score_fpga          <= 8'd0;
            question_used       <= 10'b0;
            selected_question   <= 4'd0;
            last_answer_correct <= 1'b0;
            bus_owner           <= BUS_IDLE;
            txfsm_start         <= 1'b0;
            txfsm_q_idx         <= 4'd0;
            ac_enable           <= 1'b0;
            rs_send_result      <= 1'b0;
            rs_result_correct   <= 1'b0;
            rs_send_score       <= 1'b0;
            rs_send_gameover    <= 1'b0;
            led                 <= 4'b0000;
        end else begin
            // Defaults: pulsos de 1 ciclo
            txfsm_start      <= 1'b0;
            rs_send_result   <= 1'b0;
            rs_send_score    <= 1'b0;
            rs_send_gameover <= 1'b0;

            case (game_state)

                // =============================================================
                // IDLE: Esperar botón de inicio para nueva partida
                // =============================================================
                G_IDLE: begin
                    bus_owner <= BUS_IDLE;
                    ac_enable <= 1'b0;
                    led[3]    <= locked; // LED3 = PLL locked

                    if (btn_start_pulse) begin
                        // Iniciar nueva partida
                        round_count   <= 3'd0;
                        score_pc      <= 8'd0;
                        score_fpga    <= 8'd0;
                        question_used <= 10'b0;
                        game_state    <= G_SELECT_QUESTION;
                    end
                end

                // =============================================================
                // SELECT_QUESTION: Seleccionar pregunta pseudoaleatoria
                // =============================================================
                G_SELECT_QUESTION: begin
                    selected_question <= find_unused_question(lfsr, question_used);
                    game_state        <= G_SEND_QUESTION;
                end

                // =============================================================
                // SEND_QUESTION: Iniciar transmisión de pregunta por UART
                // =============================================================
                G_SEND_QUESTION: begin
                    question_idx  <= selected_question;
                    txfsm_q_idx   <= selected_question;
                    txfsm_start   <= 1'b1;
                    bus_owner     <= BUS_TX_FSM;
                    question_used <= question_used_next; // Marcar como usada
                    led[0]        <= 1'b1; // LED0 = transmitiendo pregunta
                    game_state    <= G_WAIT_TX_DONE;
                end

                // =============================================================
                // WAIT_TX_DONE: Esperar que se envíe toda la pregunta
                // =============================================================
                G_WAIT_TX_DONE: begin
                    if (txfsm_done) begin
                        led[0]     <= 1'b0;
                        bus_owner  <= BUS_ANS_CHECK;
                        ac_enable  <= 1'b1;
                        game_state <= G_WAIT_ANSWER;
                    end
                end

                // =============================================================
                // WAIT_ANSWER: Esperar respuesta del jugador PC
                // =============================================================
                G_WAIT_ANSWER: begin
                    led[1] <= 1'b1; // LED1 = esperando respuesta

                    if (ac_answer_valid) begin
                        led[1]              <= 1'b0;
                        ac_enable           <= 1'b0;
                        last_answer_correct <= ac_answer_correct;
                        game_state          <= G_PROCESS_ANSWER;
                    end
                    // Bytes inválidos son ignorados por answer_checker
                end

                // =============================================================
                // PROCESS_ANSWER: Actualizar score
                // =============================================================
                G_PROCESS_ANSWER: begin
                    if (last_answer_correct) begin
                        score_pc <= score_pc + 8'd1;
                        led[2]   <= 1'b1; // LED2 = respuesta correcta
                    end else begin
                        led[2]   <= 1'b0;
                    end
                    game_state <= G_SEND_RESULT;
                end

                // =============================================================
                // SEND_RESULT: Enviar resultado al jugador PC
                // =============================================================
                G_SEND_RESULT: begin
                    bus_owner         <= BUS_RES_SEND;
                    rs_send_result    <= 1'b1;
                    rs_result_correct <= last_answer_correct;
                    game_state        <= G_WAIT_RESULT_DONE;
                end

                // =============================================================
                // WAIT_RESULT_DONE
                // =============================================================
                G_WAIT_RESULT_DONE: begin
                    if (rs_done) begin
                        game_state <= G_SEND_SCORE;
                    end
                end

                // =============================================================
                // SEND_SCORE: Enviar score actualizado
                // =============================================================
                G_SEND_SCORE: begin
                    rs_send_score <= 1'b1;
                    game_state    <= G_WAIT_SCORE_DONE;
                end

                // =============================================================
                // WAIT_SCORE_DONE
                // =============================================================
                G_WAIT_SCORE_DONE: begin
                    if (rs_done) begin
                        game_state <= G_NEXT_ROUND;
                    end
                end

                // =============================================================
                // NEXT_ROUND: Verificar si quedan rondas
                // =============================================================
                G_NEXT_ROUND: begin
                    led[2] <= 1'b0;
                    if (round_count == 3'd6) begin
                        // 7 rondas completadas (rondas 0-6)
                        game_state <= G_GAME_OVER;
                    end else begin
                        round_count <= round_count + 3'd1;
                        game_state  <= G_SELECT_QUESTION;
                    end
                end

                // =============================================================
                // GAME_OVER: Enviar fin de partida
                // =============================================================
                G_GAME_OVER: begin
                    bus_owner        <= BUS_RES_SEND;
                    rs_send_gameover <= 1'b1;
                    game_state       <= G_WAIT_GAMEOVER_DONE;
                end

                // =============================================================
                // WAIT_GAMEOVER_DONE
                // =============================================================
                G_WAIT_GAMEOVER_DONE: begin
                    if (rs_done) begin
                        led        <= 4'b1111; // Todos LEDs = fin de partida
                        game_state <= G_IDLE;
                    end
                end

                default: game_state <= G_IDLE;
            endcase
        end
    end

endmodule

