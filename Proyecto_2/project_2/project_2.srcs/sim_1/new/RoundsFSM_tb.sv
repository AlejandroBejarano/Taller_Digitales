module testbenchRoundsFSM();
    logic clk;
    logic rst;
    logic responseP1;
    logic responseP2;
    logic pt;

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
    top dut(clk, rst, responseP1, responseP2, pt);

    // Apply inputs aligned to clock edges
    initial begin
        responseP1 = 0;
        responseP2 = 0;
        @(posedge clk); #0.1; responseP1 = 0;
        #10;
        $finish;
    end
endmodule
//module not finished