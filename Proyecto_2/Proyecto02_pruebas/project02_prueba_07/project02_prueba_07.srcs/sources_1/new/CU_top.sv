// =============================================================================
// CU_top.sv - Unidad de Control Maestra y Datapath para Jeopardy
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
    // Manejo del Timer Programable Integrado
    // =========================================================================
    logic       timer_run;
    logic       timer_load;
    logic [5:0] timer_load_val;
    logic       timer_timeout;
    
    // 1 segundo = 16,000,000 ciclos a 16MHz
    logic [23:0] sec_counter;
    
    always_ff @(posedge clk_16MHz) begin
        if (rst) begin
            sec_counter   <= '0;
            timer_val_o   <= 6'd0;
            timer_timeout <= 1'b0;
        end else begin
            if (timer_load) begin
                sec_counter   <= '0;
                timer_val_o   <= timer_load_val;
                timer_timeout <= 1'b0;
            end else if (timer_run) begin
                if (timer_val_o > 0) begin
                    // Contador de 1 segundo
                    if (sec_counter == 24'd16_000_000 - 1) begin
                        sec_counter <= '0;
                        timer_val_o <= timer_val_o - 1;
                        if (timer_val_o == 6'd1) begin
                            timer_timeout <= 1'b1; // Llega a 0 en este último tick
                        end else begin
                            timer_timeout <= 1'b0;
                        end
                    end else begin
                        sec_counter   <= sec_counter + 1;
                        timer_timeout <= 1'b0;
                    end
                end else begin
                    timer_timeout <= 1'b0;
                end
            end else begin
                timer_timeout <= 1'b0;
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
        ST_PREP_LATCH,
        ST_PREP_WAIT,
        ST_DONE
    } state_t;

    state_t state;
    
    logic fpga_locked; // Candados si el jugador falló
    logic pc_locked;
    
    always_ff @(posedge clk_16MHz) begin
        if (rst) begin
            state         <= ST_IDLE;
            rng_enable    <= 0;
            lcd_enable_o  <= 0;
            uart_enable_o <= 0;
            timer_run     <= 0;
            timer_load    <= 0;
            timer_load_val<= 0;
            play_ok_o     <= 0;
            play_error_o  <= 0;
            scoreA_o      <= 0;
            scoreB_o      <= 0;
            fpga_locked   <= 0;
            pc_locked     <= 0;
        end else begin
            // Valores por defecto de los pulsos combinacionales
            lcd_enable_o  <= 0;
            uart_enable_o <= 0;
            play_ok_o     <= 0;
            play_error_o  <= 0;
            timer_load    <= 0;

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
                        rng_enable  <= 1;
                        fpga_locked <= 0;
                        pc_locked   <= 0;
                        state       <= ST_WAIT_Q;
                    end
                end

                ST_WAIT_Q: begin
                    if (q_ready) begin
                        rng_enable    <= 0;
                        lcd_enable_o  <= 1; // Dispara LCD
                        uart_enable_o <= 1; // Dispara UART
                        state         <= ST_START_RD;
                    end
                end

                ST_START_RD: begin
                    timer_load     <= 1;
                    timer_load_val <= 6'd30; // Carga 30 Segundos
                    timer_run      <= 1;
                    state          <= ST_PLAYING;
                end

                ST_PLAYING: begin
                    // Procesar eventos de respuesta
                    if (fpga_ans_valid_i && !fpga_locked) begin
                        state <= ST_EVAL_FPGA;
                    end else if (pc_ans_valid_i && !pc_locked) begin
                        state <= ST_EVAL_PC;
                    end else if (timer_timeout) begin
                        // Se agotó el tiempo y no acertaron
                        play_error_o <= 1;
                        state        <= ST_PREP_LATCH;
                    end
                end

                ST_EVAL_FPGA: begin
                    if (fpga_ans_correct_i) begin
                        scoreA_o  <= scoreA_o + 1;
                        play_ok_o <= 1;
                        // Acertó: Corta el timer y termina la ronda
                        state     <= ST_PREP_LATCH;
                    end else begin
                        // Falló: Lo bloqueamos y suena error, pero la ronda sigue!
                        fpga_locked  <= 1;
                        play_error_o <= 1;
                        if (pc_locked == 1'b1) begin 
                            // Si el otro TAMBIÉN falló antes, doble fallo, abortamos la ronda.
                            state <= ST_PREP_LATCH;
                        end else begin
                            state <= ST_PLAYING; // Vuelve a esperar al otro
                        end
                    end
                end

                ST_EVAL_PC: begin
                    if (pc_ans_correct_i) begin
                        scoreB_o  <= scoreB_o + 1;
                        play_ok_o <= 1;
                        state     <= ST_PREP_LATCH;
                    end else begin
                        pc_locked    <= 1;
                        play_error_o <= 1;
                        if (fpga_locked == 1'b1) begin
                            state <= ST_PREP_LATCH;
                        end else begin
                            state <= ST_PLAYING;
                        end
                    end
                end

                ST_PREP_LATCH: begin
                    // Instante intermedio para configurar el Timer de espera (10s)
                    timer_load     <= 1;
                    timer_load_val <= 6'd10;
                    timer_run      <= 1;
                    state          <= ST_PREP_WAIT;
                end

                ST_PREP_WAIT: begin
                    // Cuenta regresiva visible de 10 a 0 entre pregunta y pregunta
                    if (timer_timeout) begin
                        timer_run <= 0;
                        state     <= ST_GEN_Q; // Pasa automáticamente a la sig ronda
                    end
                end

                ST_DONE: begin
                    // El juego acabó (7 rondas). El script de PC detectará el EOT de la uart_interface.
                    timer_run <= 0;
                end
            endcase
        end
    end

endmodule
