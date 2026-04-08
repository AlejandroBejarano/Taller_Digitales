`timescale 1ns / 1ps

module timeCounter_tb();

    logic clk;
    logic rst;
    logic rst_i;
    logic tA;
    logic tB;
    logic time_tie;
    logic tA_1;
    logic tB_1;

    initial begin
        clk   = 0;
        rst   = 0;
        rst_i = 0;
        tA    = 0;
        tB    = 0;
    end

    always #5 clk = ~clk;

    timeCounter dut (
        .clk      (clk),
        .rst      (rst),
        .rst_i    (rst_i),
        .tA       (tA),
        .tB       (tB),
        .time_tie (time_tie),
        .tA_1     (tA_1),
        .tB_1     (tB_1)
    );

    task wait_clk;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
            #1;
        end
    endtask

    task check;
        input exp_tA_1;
        input exp_tB_1;
        input exp_tie;
        input [127:0] msg;
        begin
            if (tA_1 !== exp_tA_1 || tB_1 !== exp_tB_1 || time_tie !== exp_tie)
                $display("FAIL [%0s] @ %0t | tA_1=%b tB_1=%b tie=%b | expected tA_1=%b tB_1=%b tie=%b",
                          msg, $time, tA_1, tB_1, time_tie, exp_tA_1, exp_tB_1, exp_tie);
            else
                $display("PASS [%0s] @ %0t | tA_1=%b tB_1=%b tie=%b",
                          msg, $time, tA_1, tB_1, time_tie);
        end
    endtask

    initial begin
        $dumpfile("timeCounter_tb.vcd");
        $dumpvars(0, timeCounter_tb);

        // Reset
        rst = 1; wait_clk(2); rst = 0;

        // =============================================
        // TEST 1: Player A buzzes before Player B
        // =============================================
        wait_clk(5);   // A buzzes after 5 cycles
        tA = 1; wait_clk(1); tA = 0;
        wait_clk(3);   // B buzzes 3 cycles later
        tB = 1; wait_clk(1); tB = 0;
        wait_clk(2);
        check(1, 0, 0, "A buzzes first");

        // =============================================
        // TEST 2: Player B buzzes before Player A
        // =============================================
        rst = 1; wait_clk(2); rst = 0;
        wait_clk(3);   // B buzzes after 3 cycles
        tB = 1; wait_clk(1); tB = 0;
        wait_clk(5);   // A buzzes 5 cycles later
        tA = 1; wait_clk(1); tA = 0;
        wait_clk(2);
        check(0, 1, 0, "B buzzes first");

        // =============================================
        // TEST 3: Tie - both buzz same cycle
        // =============================================
        rst = 1; wait_clk(2); rst = 0;
        wait_clk(5);
        tA = 1; tB = 1; wait_clk(1); tA = 0; tB = 0;
        wait_clk(2);
        check(0, 0, 1, "tie same cycle");

        // =============================================
        // TEST 4: rst_i resets mid-game
        // =============================================
        rst = 1; wait_clk(2); rst = 0;
        wait_clk(5);
        tA = 1; wait_clk(1); tA = 0;  // A buzzes
        wait_clk(2);
        rst_i = 1; wait_clk(1); rst_i = 0;  // timer pulse resets
        wait_clk(2);
        // after rst_i both counters should be cleared
        // neither locked so no winner yet
        check(0, 0, 0, "rst_i clears mid-game");

        // =============================================
        // TEST 5: Only A buzzes, B never buzzes
        // =============================================
        rst = 1; wait_clk(2); rst = 0;
        wait_clk(5);
        tA = 1; wait_clk(1); tA = 0;
        wait_clk(10);
        // B never buzzed so lockedB=0, no result yet
        check(0, 0, 0, "only A buzzed no result yet");

        $display("Testbench complete.");
        $finish;
    end

endmodule