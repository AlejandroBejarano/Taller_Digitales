`timescale 1ns / 1ps

module turnDecider_tb();

    logic clk, rst, rst_i;
    logic tA_1, tB_1, time_tie;
    logic no_answer, both_first, playerA_first, playerB_first;
    logic [3:0] n;

    initial begin
        clk=0; rst=0; rst_i=0;
        tA_1=0; tB_1=0; time_tie=0;
    end

    always #5 clk = ~clk;

    turnDecider dut (
        .clk(clk), .rst(rst), .rst_i(rst_i),
        .tA_1(tA_1), .tB_1(tB_1), .time_tie(time_tie),
        .no_answer(no_answer), .both_first(both_first),
        .playerA_first(playerA_first), .playerB_first(playerB_first),
        .n(n)
    );

    task wait_clk;
        input integer c;
        integer i;
        begin
            for(i=0;i<c;i=i+1) @(posedge clk);
            #1;
        end
    endtask

    initial begin
        $dumpfile("turnDecider_tb.vcd");
        $dumpvars(0, turnDecider_tb);

        // Reset
        rst=1; wait_clk(2); rst=0;

        // No answer yet
        wait_clk(2);

        // Player A buzzes
        tA_1=1; wait_clk(1); tA_1=0;

        // B buzzes after A - result should not change
        tB_1=1; wait_clk(1); tB_1=0;

        // rst_i fires - new round
        rst_i=1; wait_clk(1); rst_i=0;
        wait_clk(1);


        // Player B buzzes first this round
        tB_1=1; wait_clk(1); tB_1=0;

        // rst_i fires again
        rst_i=1; wait_clk(1); rst_i=0;
        wait_clk(1);

        // Tie
        tA_1=1; tB_1=1; wait_clk(1); tA_1=0; tB_1=0;

        // Hard reset
        rst=1; wait_clk(2); rst=0;
        wait_clk(1);

        $finish;
    end

endmodule