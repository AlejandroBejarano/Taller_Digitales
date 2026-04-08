`timescale 1ns/1ps

module tb_pointDeterminer;

    // Signals
    logic clk;
    logic rst;
    logic rst_i;
    logic responseP1;
    logic responseP2;
    logic pt;
    logic playerA_first;
    logic playerB_first;
    logic both_first;

    logic scoreA;
    logic scoreB;

    // DUT
    pointDeterminer dut (
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

    // Clock
    always #5 clk = ~clk;

    initial begin
        // Init
        clk = 0;
        rst = 1;
        rst_i = 0;
        pt = 0;
        responseP1 = 0;
        responseP2 = 0;
        playerA_first = 0;
        playerB_first = 0;
        both_first = 0;

        #10;
        rst = 0;

        // =========================
        // TEST 1: A answers first and correct
        // =========================
        pt = 1;
        playerA_first = 1;
        responseP1 = 1;

        #10;
        $display("TEST1 -> scoreA=%0d scoreB=%0d", scoreA, scoreB);

        // Reset control signals
        playerA_first = 0;
        responseP1 = 0;

        // =========================
        // TEST 2: B answers first and correct
        // =========================
        pt = 1;
        playerB_first = 1;
        responseP2 = 1;

        #10;
        $display("TEST2 -> scoreA=%0d scoreB=%0d", scoreA, scoreB);

        playerB_first = 0;
        responseP2 = 0;

        // =========================
        // TEST 3: No point trigger (pt=0)
        // =========================
        pt = 0;
        playerA_first = 1;
        responseP1 = 1;

        #10;
        $display("TEST3 -> scoreA=%0d scoreB=%0d (should HOLD)", scoreA, scoreB);

        playerA_first = 0;
        responseP1 = 0;

        // =========================
        // TEST 4: Wrong answer (no increment)
        // =========================
        pt = 1;
        playerA_first = 1;
        responseP1 = 0;

        #10;
        $display("TEST4 -> scoreA=%0d scoreB=%0d (no change)", scoreA, scoreB);

        playerA_first = 0;

        // =========================
        // TEST 5: Both first (should NOT work due to bug)
        // =========================
        pt = 1;
        both_first = 1;
        responseP1 = 1;

        #10;
        $display("TEST5 -> scoreA=%0d scoreB=%0d (likely no change due to logic bug)", scoreA, scoreB);

        both_first = 0;
        responseP1 = 0;

        // =========================
        // TEST 6: Reset
        // =========================
        rst = 1;
        #10;
        rst = 0;

        $display("TEST6 -> scoreA=%0d scoreB=%0d (should be 0,0)", scoreA, scoreB);

        #20;
        $finish;
    end

endmodule