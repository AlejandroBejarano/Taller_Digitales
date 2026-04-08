`timescale 1ns/1ps

module tb_LFSRandcompany;

    // signals - widths must match the top module ports
    logic        clk;
    logic        rst;
    logic        rst_i;
    logic        enable;
    logic [3:0]  i_Seed_Data;
    logic [1:0]  answer_p1;
    logic [1:0]  answer_p2;
    logic        tA;
    logic        tB;

    // outputs
    logic        pt;
    logic        playerA_first;
    logic        playerB_first;
    logic        both_first;
    logic [3:0]  scoreA;
    logic [3:0]  scoreB;

    // instantiate the full top - not just pointDeterminer
    topLFSRandcompany dut (
        .clk          (clk),
        .rst          (rst),
        .rst_i        (rst_i),
        .enable       (enable),
        .i_Seed_Data  (i_Seed_Data),
        .answer_p1    (answer_p1),
        .answer_p2    (answer_p2),
        .tA           (tA),
        .tB           (tB),
        .pt           (pt),
        .playerA_first(playerA_first),
        .playerB_first(playerB_first),
        .both_first   (both_first),
        .scoreA       (scoreA),
        .scoreB       (scoreB)
    );

    // clock
    initial clk = 0;
    always #5 clk = ~clk;

    // task: simulate one question round
    task automatic play_round(
        input [1:0] p1_ans,
        input [1:0] p2_ans,
        input        p1_first   // 1 = P1 buzzed first, 0 = P2 buzzed first
    );
        // enable RNG to advance to next question
        enable = 1;
        repeat(4) @(posedge clk);
        enable = 0;
        @(posedge clk);

        // submit answers - stagger if one player is first
        answer_p1 = p1_ans;
        answer_p2 = p2_ans;

        if (p1_first) begin
            tA = 1; @(posedge clk); #1; tA = 0;
            @(posedge clk);
            tB = 1; @(posedge clk); #1; tB = 0;
        end else begin
            tB = 1; @(posedge clk); #1; tB = 0;
            @(posedge clk);
            tA = 1; @(posedge clk); #1; tA = 0;
        end

        @(posedge clk); #1;
        $display("Round done | scoreA=%0d scoreB=%0d | pt=%0b playerA_first=%0b playerB_first=%0b both_first=%0b",
            scoreA, scoreB, pt, playerA_first, playerB_first, both_first);
    endtask

    initial begin
        // initialise all inputs
        rst          = 1;
        rst_i        = 0;
        enable       = 0;
        i_Seed_Data  = 4'b1011;   // seed from switches - must not be 0
        answer_p1    = 2'b00;
        answer_p2    = 2'b00;
        tA           = 0;
        tB           = 0;

        // reset for 2 cycles
        repeat(2) @(posedge clk);
        rst = 0;
        @(posedge clk);

        $display("--- test 1: P1 correct first, P2 wrong ---");
        play_round(2'b10, 2'b01, 1);  // adjust answers to match your answer_table

        $display("--- test 2: P2 correct first, P1 wrong ---");
        play_round(2'b01, 2'b00, 0);

        $display("--- test 3: both correct, P1 first ---");
        play_round(2'b00, 2'b00, 1);

        $display("--- test 4: both wrong ---");
        play_round(2'b11, 2'b10, 1);

        $display("--- test 5: mid-round rst_i pulse ---");
        enable = 1;
        repeat(4) @(posedge clk);
        enable = 0;
        rst_i = 1; @(posedge clk); #1;
        rst_i = 0;
        @(posedge clk); #1;
        $display("After rst_i | scoreA=%0d scoreB=%0d", scoreA, scoreB);

        $display("--- test 6: full rst ---");
        rst = 1; @(posedge clk); #1;
        rst = 0; @(posedge clk); #1;
        $display("After rst | scoreA=%0d scoreB=%0d", scoreA, scoreB);
        if (scoreA !== 0 || scoreB !== 0)
            $display("FAIL: scores should be 0 after rst");
        else
            $display("PASS: scores cleared");

        $display("--- all tests done ---");
        $finish;
    end

endmodule