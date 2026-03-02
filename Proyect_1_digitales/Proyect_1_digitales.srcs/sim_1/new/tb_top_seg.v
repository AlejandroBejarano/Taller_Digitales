`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/01/2026 09:37:35 PM
// Design Name: 
// Module Name: tb_top_seg
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_top_seg;

    // ==========================
    // Señales
    // ==========================
    reg clk;
    reg [6:0] attempts;
    reg [3:0] steps;

    wire [6:0] seg;
    wire [3:0] an;

    // ==========================
    // DUT
    // ==========================
    top_seg DUT (
        .clk(clk),
        .attempts(attempts),
        .steps(steps),
        .seg(seg),
        .an(an)
    );

    // ==========================
    // Clock 100 MHz (10 ns periodo)
    // ==========================
    initial clk = 0;
    always #5 clk = ~clk;

    // ==========================
    // Waveform dump
    // ==========================
    initial begin
        $dumpfile("tb_top_seg.vcd");
        $dumpvars(0, tb_top_seg);
    end

    // ==========================
    // Estímulos
    // ==========================
    initial begin

        //--------------------------------------------------
        // Caso 1
        //--------------------------------------------------
        attempts = 7'd37;
        steps    = 4'd2;

        // Mantener señal estable para observar multiplexado
        #5000000;   // 5 ms

        //--------------------------------------------------
        // Caso 2
        //--------------------------------------------------
        attempts = 7'd08;
        steps    = 4'd5;

        #5000000;

        //--------------------------------------------------
        // Caso 3
        //--------------------------------------------------
        attempts = 7'd99;
        steps    = 4'd7;

        #5000000;

        //--------------------------------------------------
        // Caso 4
        //--------------------------------------------------
        attempts = 7'd45;
        steps    = 4'd3;

        #5000000;

        //--------------------------------------------------
        // Finish
        //--------------------------------------------------
        #10000000;
        $finish;
    end

    // ==========================
    // Monitor consola
    // ==========================
    initial begin
        $monitor("T=%0t | attempts=%d | steps=%d | an=%b | seg=%b",
                 $time, attempts, steps, an, seg);
    end

endmodule