// =============================================================================
// CU_top.sv - Unidad de Control Maestra del Juego Jeopardy
//
// Responsabilidades:
//   - Genera aleatoriamente la secuencia de 7 preguntas (LFSR + question_selector).
//   - Controla el temporizador programable de 30 s (jugada) y 10 s (preparación).
//   - Arbitra las respuestas de ambos jugadores (FPGA y PC) con sistema de candado.
//   - Lleva el marcador de ambos jugadores (scoreA = FPGA, scoreB = PC).
//   - Emite pulsos de audio (play_ok_o, play_error_o) y señal de ronda terminada.
//
// Entradas principales:
//   clk_16MHz       – Reloj del sistema (16 MHz desde PLL).
//   rst             – Reset activo alto, sincronizado.
//   btn_ok_i        – Botón START: inicia una nueva partida desde ST_IDLE.
//   fpga_ans_valid_i – Pulso: el jugador FPGA confirmó su respuesta (lcd_fsm).
//   fpga_ans_correct_i – Nivel: la respuesta del FPGA es correcta.
//   pc_ans_valid_i  – Pulso: el jugador PC envió una respuesta válida (A/B/C/D).
//   pc_ans_correct_i – Nivel: la respuesta del PC es correcta.
//
// Salidas principales:
//   lcd_enable_o    – Pulso de 1 ciclo: ordena a lcd_fsm cargar nueva pregunta.
//   uart_enable_o   – Pulso de 1 ciclo: ordena a uart_tx_fsm transmitir nueva pregunta.
//   question_idx_o  – Índice (0-9) de la pregunta seleccionada en la ROM.
//   play_ok_o       – Pulso de 1 ciclo: respuesta correcta → buzzer OK.
//   play_error_o    – Pulso de 1 ciclo: respuesta incorrecta o timeout → buzzer ERROR.
//   round_over_o    – Pulso de 1 ciclo: la ronda terminó (justo antes del prep 10 s).
//   timer_val_o     – Valor actual del temporizador visible en display 7-segmentos.
//   scoreA_o        – Puntaje acumulado del jugador FPGA (4 bits).
//   scoreB_o        – Puntaje acumulado del jugador PC   (4 bits).
//
// FSM principal (state_t):
//   ST_IDLE      – Espera btn_ok para iniciar partida. Resetea marcadores.
//   ST_GEN_Q     – Verifica si quedan rondas; activa generador RNG.
//   ST_WAIT_Q    – Espera a que question_selector valide índice aleatorio.
//   ST_START_RD  – Carga timer a 30 s y habilita LCD/UART para nueva pregunta.
//   ST_PLAYING   – Ronda activa: monitorea respuestas y timeout de 30 s.
//   ST_EVAL_FPGA – Evalúa respuesta del jugador FPGA (correcto/incorrecto).
//   ST_EVAL_PC   – Evalúa respuesta del jugador PC   (correcto/incorrecto).
//   ST_POST_RND  – Congela la pantalla 2 s con el resultado (freeze_cnt).
//   ST_PREP_LATCH– Carga timer a 10 s y lo pone en marcha.
//   ST_PREP_WAIT – Cuenta regresiva de 10 s antes de la siguiente pregunta.
//   ST_DONE      – 7 rondas completadas; estado final congelado.
// =============================================================================
`timescale 1ns / 1ps

module CU_top (
    input  logic        clk_16MHz,
    input  logic        rst,

    // Boton START (inicia el juego)
    input  logic        btn_ok_i,

    // Interface con LFSR / Selector
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
    output logic        round_over_o,  // Pulso: la ronda terminó (justo antes de prep 10s)

    output logic [5:0]  timer_val_o,
    output logic [3:0]  scoreA_o,     // Jugador FPGA
    output logic [3:0]  scoreB_o      // Jugador PC
);

    // =========================================================================
    // Instanciación de RNG (Datapath)
    // =========================================================================
    // rng_enable  – habilita el LFSR y random_number para buscar índice libre
    // lfsr_data   – valor de 4 bits del LFSR (semilla del número aleatorio)
    // rng_number  – número 0-9 validado por random_number
    // rng_valid   – pulso: rng_number contiene un valor usable
    // q_ready     – pulso: question_selector confirma índice listo
    // round_done  – nivel: ya se eligieron 7 preguntas distintas
    // current_q_idx – índice de pregunta actualmente seleccionado
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
    // timer_run       – 1 = contar; 0 = pausar/resetear timeout
    // timer_load      – pulso de 1 ciclo: carga timer_load_val en el contador
    // timer_load_val  – valor inicial a cargar (6 bits: máx 63 s)
    // timer_timeout   – pulso de 1 ciclo: el timer llegó a 0
    // sec_counter     – contador de ciclos para generar flancos de 1 segundo
    logic       timer_run;
    logic       timer_load;
    logic [5:0] timer_load_val;
    logic       timer_timeout;

    // 1 segundo = 16,000,000 ciclos a 16MHz
    logic [24:0] sec_counter;

    always_ff @(posedge clk_16MHz) begin
        if (rst) begin
            sec_counter   <= '0;
            timer_val_o   <= 6'd0;
            timer_timeout <= 1'b0;
        end else begin
            if (timer_load) begin
                // Carga inmediata: resetea contador y coloca valor inicial
                sec_counter   <= '0;
                timer_val_o   <= timer_load_val;
                timer_timeout <= 1'b0;
            end else if (timer_run) begin
                if (timer_val_o > 0) begin
                    // Contador de 1 segundo
                    if (sec_counter == 25'd16_000_000 - 1) begin
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
                // Timer detenido: limpiar timeout para no dejar señal espuria
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
        ST_POST_RND,       // Estado de congelamiento (Muestra la pantalla post victoria/derrota 2s)
        ST_PREP_LATCH,
        ST_PREP_WAIT,
        ST_DONE
    } state_t;

    state_t state;

    // fpga_locked / pc_locked – impide que un jugador que ya falló vuelva a responder
    // freeze_cnt – contador hardware de 2 s para el estado ST_POST_RND
    logic fpga_locked;
    logic pc_locked;
    logic [25:0] freeze_cnt; // Para contar 2 segundos a 16MHz (32,000,000)

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
            round_over_o  <= 0;
            scoreA_o      <= 0;
            scoreB_o      <= 0;
            fpga_locked   <= 0;
            pc_locked     <= 0;
            freeze_cnt    <= 0;
        end else begin
            // Valores por defecto de los pulsos combinacionales
            lcd_enable_o  <= 0;
            uart_enable_o <= 0;
            play_ok_o     <= 0;
            play_error_o  <= 0;
            round_over_o  <= 0;
            timer_load    <= 0;

            case (state)
                // -----------------------------------------------------------------
                // ST_IDLE: Espera btn_ok. Resetea marcadores y candados de ronda.
                // -----------------------------------------------------------------
                ST_IDLE: begin
                    scoreA_o <= 0;
                    scoreB_o <= 0;
                    if (btn_ok_i) begin // START general
                        state <= ST_GEN_Q;
                    end
                end

                // -----------------------------------------------------------------
                // ST_GEN_Q: Comprueba si ya se jugaron 7 rondas; si no, activa RNG.
                // -----------------------------------------------------------------
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

                // -----------------------------------------------------------------
                // ST_WAIT_Q: Espera confirmación del question_selector (q_ready).
                //            Emite pulsos de enable para LCD y UART.
                // -----------------------------------------------------------------
                ST_WAIT_Q: begin
                    if (q_ready) begin
                        rng_enable    <= 0;
                        lcd_enable_o  <= 1; // Dispara LCD
                        uart_enable_o <= 1; // Dispara UART
                        state         <= ST_START_RD;
                    end
                end

                // -----------------------------------------------------------------
                // ST_START_RD: Carga el timer a 30 s y lo pone en marcha.
                // -----------------------------------------------------------------
                ST_START_RD: begin
                    timer_load     <= 1;
                    timer_load_val <= 6'd30; // Carga 30 Segundos completos
                    timer_run      <= 1;
                    state          <= ST_PLAYING;
                end

                // -----------------------------------------------------------------
                // ST_PLAYING: Ronda activa.
                //   Prioridad: FPGA responde > PC responde > timeout de 30 s.
                //   Si un jugador ya falló (locked), no puede volver a responder.
                // -----------------------------------------------------------------
                ST_PLAYING: begin
                    // Procesar eventos de respuesta
                    if (fpga_ans_valid_i && !fpga_locked) begin
                        state <= ST_EVAL_FPGA;
                    end else if (pc_ans_valid_i && !pc_locked) begin
                        state <= ST_EVAL_PC;
                    end else if (timer_timeout) begin
                        // Se agotó el tiempo (llego a 00) y no acertaron
                        play_error_o <= 1;
                        round_over_o <= 1;
                        timer_run    <= 0;
                        state        <= ST_POST_RND;
                    end
                end

                // -----------------------------------------------------------------
                // ST_EVAL_FPGA: Evalúa la respuesta del jugador FPGA.
                //   Correcto → suma punto, cierra ronda.
                //   Incorrecto → bloquea FPGA; si PC también fallará → cierra ronda.
                // -----------------------------------------------------------------
                ST_EVAL_FPGA: begin
                    if (fpga_ans_correct_i) begin
                        scoreA_o     <= scoreA_o + 1;
                        play_ok_o    <= 1;
                        round_over_o <= 1;
                        timer_run    <= 0; // Congelamos el tiempo donde respondio
                        state        <= ST_POST_RND;
                    end else begin
                        // Falló: Lo bloqueamos y suena error, pero la ronda sigue
                        fpga_locked  <= 1;
                        play_error_o <= 1;
                        if (pc_locked == 1'b1) begin
                            // Ambos fallaron: Terminamos ya temprano, truncamos el reloj
                            round_over_o <= 1;
                            timer_run    <= 0;
                            state        <= ST_POST_RND;
                        end else begin
                            state <= ST_PLAYING; // Vuelve a esperar al otro
                        end
                    end
                end

                // -----------------------------------------------------------------
                // ST_EVAL_PC: Evalúa la respuesta del jugador PC.
                //   Correcto → suma punto, cierra ronda.
                //   Incorrecto → bloquea PC; si FPGA también falló → cierra ronda.
                // -----------------------------------------------------------------
                ST_EVAL_PC: begin
                    if (pc_ans_correct_i) begin
                        scoreB_o     <= scoreB_o + 1;
                        play_ok_o    <= 1;
                        round_over_o <= 1;
                        timer_run    <= 0;
                        state        <= ST_POST_RND;
                    end else begin
                        pc_locked    <= 1;
                        play_error_o <= 1;
                        if (fpga_locked == 1'b1) begin
                            round_over_o <= 1;
                            timer_run    <= 0;
                            state        <= ST_POST_RND;
                        end else begin
                            state <= ST_PLAYING;
                        end
                    end
                end

                // -----------------------------------------------------------------
                // ST_POST_RND: Congela la pantalla 2 s para que los jugadores
                //              asimilen el resultado antes del período de prep.
                //              Usa freeze_cnt (contador hardware, no el timer).
                // -----------------------------------------------------------------
                ST_POST_RND: begin
                    // Congelar la vista por 2 segundos completos para que asuman el resultado
                    // Una vez termina este freeze de 2s, SALTA inmediatamente a la preparación de 10s
                    if (freeze_cnt == 26'd32_000_000 - 1) begin
                        freeze_cnt <= 0;
                        state      <= ST_PREP_LATCH;
                    end else begin
                        freeze_cnt <= freeze_cnt + 1;
                    end
                end

                // -----------------------------------------------------------------
                // ST_PREP_LATCH: Carga el timer a 10 s y lo arranca.
                //                Un solo ciclo; transiciona a ST_PREP_WAIT.
                // -----------------------------------------------------------------
                ST_PREP_LATCH: begin
                    // SALTA: Al configurador del Timer de espera (10s)
                    timer_load     <= 1;
                    timer_load_val <= 6'd10;
                    timer_run      <= 1;
                    state          <= ST_PREP_WAIT;
                end

                // -----------------------------------------------------------------
                // ST_PREP_WAIT: Cuenta regresiva de 10 s visible en 7-segmentos.
                //               Al terminar, va a ST_GEN_Q para la siguiente ronda.
                // -----------------------------------------------------------------
                ST_PREP_WAIT: begin
                    // Cuenta regresiva visible de 10 a 0 entre pregunta y pregunta
                    if (timer_timeout) begin
                        timer_run <= 0;
                        // Regresamos solitos a generar la siguiente de las 7 rondas
                        state     <= ST_GEN_Q;
                    end
                end

                // -----------------------------------------------------------------
                // ST_DONE: Partida terminada (7 rondas). Estado final congelado.
                // -----------------------------------------------------------------
                ST_DONE: begin
                    // El juego acabó tras generarse las 7 rondas. Queda congelado acá.
                    timer_run <= 0;
                end
            endcase
        end
    end

endmodule
