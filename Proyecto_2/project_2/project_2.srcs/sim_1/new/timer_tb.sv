`timescale 1ns / 1ps
module testbench_timer();
    logic clk;
    logic rst;
    logic rst_i;

    initial clk = 0;
    always #5 clk = ~clk; 

    initial begin
        rst = 1;
        @(posedge clk); @(posedge clk);
        rst = 0;
    end

    timer dut(clk, rst, rst_i);

    initial begin
        #300;
        $finish;
    end
endmodule
//revise nota del módulo timer