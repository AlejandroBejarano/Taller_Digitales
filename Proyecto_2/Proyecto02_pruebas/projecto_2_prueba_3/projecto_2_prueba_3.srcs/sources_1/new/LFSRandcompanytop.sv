//CAMBIO: se reescribio el modulo completo para:
// 1) Eliminar LFSR_inst y random_number_inst (redundantes: question_selector
//    ya instancia internamente su propio random_number).
// 2) Agregar instancias de timeCounter, turnDecider, firstAnswerEncoder y
//    patternMoore que faltaban para completar el datapath.
// 3) Separar las senales responseP1/responseP2 en dos pares con nombres
//    distintos: buzz_rP1/buzz_rP2 (firstAnswerEncoder -> patternMoore, indican
//    quien toco el buzzer primero) y correct_rP1/correct_rP2 (answer_checker ->
//    pointDeterminer, indican quien respondio correctamente).
// 4) Exponer ready, round_done, question_index y no_answer como outputs para
//    que game_controller pueda orquestar el flujo del juego.
// 5) Corregir el port-map de pointDeterminer: playerA_first, playerB_first y
//    both_first son INPUTS de pointDeterminer (vienen de turnDecider), no outputs.

module topLFSRandcompany (
    input  wire        clk,
    input  wire        rst,
    input  wire        rst_i,       // pulso de nueva ronda (del timer)
    input  wire        enable,      // habilita generacion de preguntas (game_controller)
    input  wire [3:0]  i_Seed_Data, // semilla LFSR (botones fisicos)
    input  wire [1:0]  answer_p1,   // respuesta jugador A (BTN_SEL cycling)
    input  wire [1:0]  answer_p2,   // respuesta jugador B (UART RX)
    input  wire        tA,          // buzzer jugador A (BTN_OK)
    input  wire        tB,          // buzzer jugador B (uart_rx_done)
    // Outputs de estado del juego
    output wire        pt,           // se asigno un punto en esta ronda
    output wire        playerA_first,
    output wire        playerB_first,
    output wire        both_first,
    output wire [3:0]  scoreA,
    output wire [3:0]  scoreB,
    // Outputs para game_controller
    output wire        ready,         // question_selector: nueva pregunta disponible
    output wire        round_done,    // question_selector: 7 preguntas completadas
    output wire [3:0]  question_index,// indice de la pregunta activa (0-9)
    output wire        no_answer      // nadie respondio en el tiempo de la ronda
);

    // =========================================================================
    // Senales internas
    // =========================================================================

    // timeCounter -> turnDecider
    wire tA_1, tB_1, time_tie;

    // turnDecider -> (firstAnswerEncoder + outputs del modulo)
    wire playerA_first_w, playerB_first_w, both_first_w, no_answer_w;

    // firstAnswerEncoder -> patternMoore (quien toco el buzzer primero)
    wire buzz_rP1, buzz_rP2;

    // answer_checker -> pointDeterminer (quien respondio correctamente)
    wire correct_rP1, correct_rP2;

    // patternMoore -> output pt + pointDeterminer
    wire pt_w;

    // =========================================================================
    // 1. timeCounter: mide quien toco el buzzer primero
    // =========================================================================
    timeCounter tc_inst (
        .clk      (clk),
        .rst      (rst),
        .rst_i    (rst_i),
        .tA       (tA),
        .tB       (tB),
        .time_tie (time_tie),
        .tA_1     (tA_1),
        .tB_1     (tB_1)
    );

    // =========================================================================
    // 2. turnDecider: decide quien respondio primero o si hubo timeout
    // =========================================================================
    turnDecider td_inst (
        .clk          (clk),
        .rst          (rst),
        .rst_i        (rst_i),
        .tA_1         (tA_1),
        .tB_1         (tB_1),
        .time_tie     (time_tie),
        .no_answer    (no_answer_w),
        .both_first   (both_first_w),
        .playerA_first(playerA_first_w),
        .playerB_first(playerB_first_w),
        .n            ()  // contador de rondas; no se usa externamente
    );

    // =========================================================================
    // 3. firstAnswerEncoder: codifica quien toco primero como senal de respuesta
    //    para patternMoore (buzz_rP1/P2 = "quien tiene turno de responder")
    // =========================================================================
    firstAnswerEncoder fae_inst (
        .no_answer    (no_answer_w),
        .playerA_first(playerA_first_w),
        .playerB_first(playerB_first_w),
        .both_first   (both_first_w),
        .responseP1   (buzz_rP1),
        .responseP2   (buzz_rP2)
    );

    // =========================================================================
    // 4. question_selector: selecciona preguntas unicas usando RNG interno
    // =========================================================================
    question_selector question_selector_inst (
        .clk           (clk),
        .rst           (rst),
        .enable        (enable),
        .question_index(question_index),
        .ready         (ready),
        .round_done    (round_done)
    );

    // =========================================================================
    // 5. answer_checker: verifica si la respuesta del jugador es correcta
    //    (correct_rP1/P2 = "quien respondio correctamente")
    // =========================================================================
    answer_checker answer_checker_inst (
        .clk           (clk),
        .rst           (rst),
        .question_index(question_index),
        .answer_p1     (answer_p1),
        .answer_p2     (answer_p2),
        .tA            (tA),
        .tB            (tB),
        .responseP1    (correct_rP1),
        .responseP2    (correct_rP2)
    );

    // =========================================================================
    // 6. patternMoore (RoundsFSM): determina si se asigna punto en la ronda
    //    basandose en quien toco el buzzer primero (buzz_rP1/P2)
    // =========================================================================
    patternMoore pm_inst (
        .clk       (clk),
        .rst       (rst),
        .rst_i     (rst_i),
        .responseP1(buzz_rP1),
        .responseP2(buzz_rP2),
        .pt        (pt_w)
    );

    // =========================================================================
    // 7. pointDeterminer: asigna puntos combinando pt (hubo intento) con
    //    correct_rP1/P2 (fue correcto) y quien respondio primero
    // =========================================================================
    pointDeterminer pointDeterminer_inst (
        .clk          (clk),
        .rst          (rst),
        .rst_i        (rst_i),
        .responseP1   (correct_rP1),
        .responseP2   (correct_rP2),
        .pt           (pt_w),
        .playerA_first(playerA_first_w),
        .playerB_first(playerB_first_w),
        .both_first   (both_first_w),
        .scoreA       (scoreA),
        .scoreB       (scoreB)
    );

    // =========================================================================
    // Asignacion de outputs
    // =========================================================================
    assign pt            = pt_w;
    assign playerA_first = playerA_first_w;
    assign playerB_first = playerB_first_w;
    assign both_first    = both_first_w;
    assign no_answer     = no_answer_w;

endmodule

