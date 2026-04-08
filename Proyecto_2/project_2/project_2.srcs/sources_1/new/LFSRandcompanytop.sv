module topLFSRandcompany (
    input  wire        clk,
    input  wire        rst,
    input  wire        rst_i,
    input  wire        enable,
    input  wire [3:0]  i_Seed_Data,
    input  wire [1:0]  answer_p1,
    input  wire [1:0]  answer_p2,
    input  wire        tA,
    input  wire        tB,
    output wire        pt,
    output wire        playerA_first,
    output wire        playerB_first,
    output wire        both_first,
    output wire [3:0]  scoreA,
    output wire [3:0]  scoreB
);

    // internal signals
    wire [3:0]  o_LFSR_Data;
    wire         o_LFSR_Done;
    wire [3:0]   number;
    wire          valid;
    wire [3:0]   question_index;
    wire          ready;
    wire          responseP1;
    wire          responseP2;

    // 1. LFSR generates raw pseudo-random bits
    LFSR LFSR_inst (
        .clk        (clk),
        .rst        (rst),
        .enable     (enable),
        .i_Seed_Data(i_Seed_Data),
        .o_LFSR_Data(o_LFSR_Data),
        .o_LFSR_Done(o_LFSR_Done)
    );

    // 2. random_1_to_10 maps LFSR output to a number in range 1-10
    random_number random_number_inst (
        .clk   (clk),
        .rst   (rst),
        .enable(enable),
        .number(number),
        .valid (valid)
    );

    // 3. question selector picks unique questions using random number
    question_selector question_selector_inst (
        .clk           (clk),
        .rst           (rst),
        .enable        (enable),
        .question_index(question_index),
        .ready         (ready),
        .round_done (round_done)
    );

    // 4. answer checker compares player answers against correct answer
    answer_checker answer_checker_inst (
        .clk           (clk),
        .rst           (rst),
        .question_index(question_index),
        .answer_p1     (answer_p1),
        .answer_p2     (answer_p2),
        .tA            (tA),
        .tB            (tB),
        .responseP1    (responseP1),
        .responseP2    (responseP2)
    );

    // 5. point determiner scores based on correctness and who answered first
    pointDeterminer pointDeterminer_inst (
        .clk          (clk),
        .rst          (rst),
        .rst_i        (rst_i),
        .responseP1   (responseP1),
        .responseP2   (responseP2),
        .pt           (pt),
        .playerA_first(playerA_first),
        .playerB_first(playerB_first),
        .both_first   (both_first),
        .scoreA       (scoreA),
        .scoreB       (scoreB)
    );

endmodule