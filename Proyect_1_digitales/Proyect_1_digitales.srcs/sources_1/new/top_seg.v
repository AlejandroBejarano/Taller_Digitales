`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/01/2026 09:29:20 PM
// Design Name: 
// Module Name: top_seg
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


module top_seg (

    input clk,
    input [6:0] attempts,     // hasta 99
    input [3:0] steps,    // hasta 9
    output [6:0] seg,
    output [3:0] an

);

    wire [3:0] unidades;
    wire [3:0] decenas;

    // Separar intentos en decenas y unidades
    assign decenas  = attempts / 10;
    assign unidades = attempts % 10;

    reg [3:0] digit;

    // Multiplexado simple (sin divisor por ahora)
    reg [1:0] sel = 0;

    always @(posedge clk)
        sel <= sel + 1;

    always @(*) begin
        case(sel)
            2'b00: digit = unidades;
            2'b01: digit = decenas;
            2'b10: digit = steps;
            default: digit = 4'd0;
        endcase
    end

    segmentos decodificador (
        .bin(digit),
        .seg(seg)
    );

    assign an = ~(4'b0001 << sel); // activar display

endmodule


