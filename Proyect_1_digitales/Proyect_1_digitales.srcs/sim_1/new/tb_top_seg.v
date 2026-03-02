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

    // =========================
    // Señales de prueba
    // =========================
    reg clk;
    reg [6:0] attempts;
    reg [3:0] steps;

    wire [6:0] seg;
    wire [3:0] an;

    // =========================
    // Instancia del DUT
    // =========================
    top_seg uut (
        .clk(clk),
        .attempts(attempts),
        .steps(steps),
        .seg(seg),
        .an(an)
    );

    // =========================
    // Generador de reloj
    // =========================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;   // periodo 10ns
    end

    // =========================
    // Estímulos
    // =========================
    initial begin
        
        // Caso 1
        attempts = 7'd23;   // debería mostrar 2 y 3
        steps    = 4'd7;    // debería mostrar 7
        #200;

        // Caso 2
        attempts = 7'd45;
        steps    = 4'd9;
        #200;

        // Caso 3
        attempts = 7'd8;
        steps    = 4'd4;
        #200;

        // Caso 4
        attempts = 7'd99;
        steps    = 4'd1;
        #200;

        $stop;
    end

    // =========================
    // Monitor en consola
    // =========================
    initial begin
        $monitor("t=%0t | attempts=%d | steps=%d | sel_display=%b | seg=%b",
                 $time, attempts, steps, an, seg);
    end

endmodule
