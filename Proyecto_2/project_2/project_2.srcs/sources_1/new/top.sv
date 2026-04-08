module top (
    input wire clk,
    input wire rst,
    input wire rst_i,
);

    timer timer_inst (
        .clk(clk),
        .rst(rst),
        .tA_1(tA_1),
        .tB_1(tB_1)
    );

    timeCounter timeCounter_inst (
        .clk(clk),
        .rst(rst),
        .tA_1(tA_1),
        .tB_1(tB_1),
        .time_tie(time_tie)
    );

    turnDecider turnDecider_inst (
        .clk(clk),
        .rst(rst),
        .rst_i(rst_i),
        .tA_1(tA_1),
        .tB_1(tB_1),
        .time_tie(time_tie),
        .no_answer(no_answer),
        .both_first(both_first),
        .playerA_first(playerA_first),
        .playerB_first(playerB_first),
        .n(n)
    );

    patternMoore patternMoore_inst (
    // ENTRADAS
     .clk       (clk),
    .rst       (rst),
    .a    (a),

    // SALIDA
    .y (y)
    );

    LFSR LFSR_inst (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .i_Seed_Data(i_Seed_Data),
        .o_LFSR_Data(o_LFSR_Data),
        .o_LFSR_Done(o_LFSR_Done)
    );
    
    questionSelector questionSelector_inst (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .question_index(question_index),
        .ready(ready),
        .round_done(round_done)
    );

    random_number random_number_inst (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .number(number),
    .valid(valid)
);

    pointDeterminer pointDeterminer_inst (
        .clk(clk),
        .rst(rst),
        .rst_i(rst_i),
        .responseP1(responseP1),
        .responseP2(responseP2), 
        .pt(pt),
        .playerA_first(playerA_first),
        .playerB_first(playerB_first),
        .both_first(both_first),
        .scoreA(scoreA),
        .scoreB(scoreB)
    );

    firstAnswerEncoder firstAnswerEncoder_inst (
        .no_answer(no_answer),
        .playerA_first(playerA_first),
        .playerB_first(playerB_first),
        .both_first(both_first),
        .responseP1(responseP1),
        .responseP2(responseP2) 
    );

    answerChecker answerChecker_inst (
        .clk(clk),
        .rst(rst),
        .question_index(question_index),
        .answer_p1(answer_p1),
        .answer_p2(answer_p2),
        .tA(tA),
        .tB(tB),
        .responseP1(responseP1),
        .responseP2(responseP2) 
    );    

    

endmodule