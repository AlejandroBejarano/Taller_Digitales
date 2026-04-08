module firstAnswerEncoder_tb();
    logic clk;
    logic rst;
    logic rst_i;
    logic no_answer;
    logic playerA_first;
    logic playerB_first;
    logic both_first;
    logic responseP1;
    logic responseP2;

    // Clock
    initial clk = 0;
    always #1 clk = ~clk;

    // Reset for 2 full clock cycles
    initial begin
        rst = 1;
        @(posedge clk); @(posedge clk);
        rst = 0;
    end

    // instantiate DUT
    firstAnswerEncoder dut(
        .no_answer(no_answer),
        .playerA_first(playerA_first),
        .playerB_first(playerB_first),
        .both_first(both_first),
        .responseP1(responseP1),
        .responseP2(responseP2)
    );

    // Apply inputs aligned to clock edges
    initial begin
        no_answer = 0;
        playerA_first = 0;
        playerB_first = 0;
        both_first = 0;
        @(posedge clk); #0.1; no_answer = 0;
        #10;
        $finish;
    end
endmodule
//module not finished