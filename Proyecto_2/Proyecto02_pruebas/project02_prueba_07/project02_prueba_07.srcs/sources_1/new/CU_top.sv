// =============================================================================
// CU_top.sv — Unidad de Control Maestra y Datapath para Jeopardy
// =============================================================================
`timescale 1ns / 1ps

module CU_top (
    input  logic        clk_16MHz,
    input  logic        rst,
    
    // Boton START (inicia el juego)
    input  logic        btn_ok_i,
    
    // Entradas desde Answer Checkers (validación ya procesada)
    input  logic        fpga_ans_valid_i,
    input  logic        fpga_ans_correct_i,
    input  logic        pc_ans_valid_i,
    input  logic        pc_ans_correct_i,

    // Interface hacia Periferiales (LCD, UART, Buzzer)
    output logic        lcd_enable_o,
    output logic        uart_enable_o,
    output logic [3:0]  question_idx_o,
    
    output logic        play_ok_o,
    output logic        play_error_o,
    
    output logic [5:0]  timer_val_o,
    output logic [3:0]  scoreA_o,     // Jugador FPGA
    output logic [3:0]  scoreB_o      // Jugador PC
);

    // =========================================================================
    // Instanciación de RNG (Datapath)
    // =========================================================================
    logic       rng_enable;
    logic [3:0] lfsr_data;
    logic [3:0] rng_number;
    logic       rng_valid;
    logic       q_ready;
    logic       round_done;
    logic [3:0] current_q_idx;

    assign question_idx_o = current_q_idx;

    LFSR #(4) u_lfsr (
        .clk(clk_16MHz), .rst(rst), .enable(1'b1),
        .i_Seed_Data(4'd3), .o_LFSR_Data(lfsr_data), .o_LFSR_Done()
    );

    random_number u_rng (
        .clk(clk_16MHz), .rst(rst), .enable(rng_enable),
        .lfsr_out(lfsr_data), .number(rng_number), .valid(rng_valid)
    );

    question_selector u_qsel (
        .clk(clk_16MHz), .rst(rst), .enable(rng_enable),
        .number(rng_number), .valid(rng_valid),
        .question_index(current_q_idx), .ready(q_ready), .round_done(round_done)
    );

    // =========================================================================
    // Manejo del Timer de 30s
    // =========================================================================
    logic timer_enable;
    logic timer_timeout;
    
    thirty_sec_timer u_timer (
        .clk(clk_16MHz), .rst(rst), .enable_i(timer_enable), .rst_i(timer_timeout)
    );
    
    // Contador de tiempo (aprox) para mostrar en el Display 7Seg (6 bits)
    // 1 segundo = 16M ciclos
    logic [23:0] sec_counter;
    always_ff @(posedge clk_16MHz) begin
        if (rst || !timer_enable) begin
            sec_counter <= '0;
            timer_val_o <= 6'd30;
        end else if (timer_enable && timer_val_o > 0) begin
            if (sec_counter == 24'd16_000_000) begin
                sec_counter <= '0;
                timer_val_o <= timer_val_o - 1;
            end else begin
                sec_counter <= sec_counter + 1;
            end
        end
    end

    // =========================================================================
    // State Machine
    // =========================================================================
    typedef enum logic [3:0] {
        ST_IDLE,
        ST_GEN_Q,
        ST_WAIT_Q,
        ST_START_RD,
        ST_PLAYING,
        ST_EVAL_FPGA,
        ST_EVAL_PC,
        ST_WAIT_END_RND,
        ST_DONE
    } state_t;

    state_t state;
    
    // Manejo de pulsos de salida
    // Estas señales se hacen 1 solo un ciclo, así que las declaramos lógicas directas
    always_ff @(posedge clk_16MHz) begin
        if (rst) begin
            state         <= ST_IDLE;
            rng_enable    <= 0;
            lcd_enable_o  <= 0;
            uart_enable_o <= 0;
            timer_enable  <= 0;
            play_ok_o     <= 0;
            play_error_o  <= 0;
            scoreA_o      <= 0;
            scoreB_o      <= 0;
        end else begin
            lcd_enable_o  <= 0;
            uart_enable_o <= 0;
            play_ok_o     <= 0;
            play_error_o  <= 0;

            case (state)
                ST_IDLE: begin
                    scoreA_o <= 0;
                    scoreB_o <= 0;
                    if (btn_ok_i) begin // START general
                        state <= ST_GEN_Q;
                    end
                end

                ST_GEN_Q: begin
                    if (round_done) begin
                        state <= ST_DONE;
                    end else begin
                        rng_enable <= 1;
                        state      <= ST_WAIT_Q;
                    end
                end

                ST_WAIT_Q: begin
                    if (q_ready) begin
                        rng_enable    <= 0;
                        lcd_enable_o  <= 1; // Avisar al LCD FSM que empiece
                        uart_enable_o <= 1; // Avisar a UART FSM que empiece
                        state         <= ST_START_RD;
                    end
                end

                ST_START_RD: begin
                    // Pequeño retardo para dejarlos iniciar
                    timer_enable <= 1; 
                    state        <= ST_PLAYING;
                end

                ST_PLAYING: begin
                    // Si alguien presionó y el Checker nos manda 'Valid'
                    if (fpga_ans_valid_i) begin
                        state <= ST_EVAL_FPGA;
                        timer_enable <= 0;
                    end else if (pc_ans_valid_i) begin
                        state <= ST_EVAL_PC;
                        timer_enable <= 0;
                    end else if (timer_timeout) begin // Se acabo el tiempo!
                        play_error_o <= 1;
                        timer_enable <= 0;
                        state        <= ST_WAIT_END_RND;
                    end
                end

                ST_EVAL_FPGA: begin
                    if (fpga_ans_correct_i) begin
                        scoreA_o  <= scoreA_o + 1;
                        play_ok_o <= 1;
                    end else begin
                        play_error_o <= 1;
                    end
                    state <= ST_WAIT_END_RND;
                end

                ST_EVAL_PC: begin
                    if (pc_ans_correct_i) begin
                        scoreB_o  <= scoreB_o + 1;
                        play_ok_o <= 1;
                    end else begin
                        play_error_o <= 1;
                    end
                    state <= ST_WAIT_END_RND;
                end

                ST_WAIT_END_RND: begin
                    // Espera a que el usuario presione START de nuevo para
                    // pasar a la SIGUIENTE pregunta
                    if (btn_ok_i) begin 
                        state <= ST_GEN_Q;
                    end
                end

                ST_DONE: begin
                    // Se jugaron las 7 rondas. Se muestra en displays el puntaje
                    // Queda bloqueado aquí hasta el Reset general de la FPGA.
                end
            endcase
        end
    end

endmodule
