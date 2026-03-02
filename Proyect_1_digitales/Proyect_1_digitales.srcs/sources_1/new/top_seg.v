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

    input clk,              // 100 MHz
    input [6:0] attempts,   // hasta 99
    input [3:0] steps,      // hasta 9
    output [6:0] seg,
    output [3:0] an

);

    wire [3:0] unidades;
    wire [3:0] decenas;

    assign decenas  = attempts / 10;
    assign unidades = attempts % 10;

    reg [3:0] digit;
    reg [1:0] sel = 0;
    
    // ==========================
    // DIVISOR PARA ~1 kHz
    // ==========================
    reg [9:0] counter = 0;
    wire refresh;
    
    assign refresh = (counter == 2);
    
    // contador divisor
    always @(posedge clk) begin
        if(counter == 2)
            counter <= 0;
        else
            counter <= counter + 1;
    end
    
    // selector de display (4 displays max)
    always @(posedge clk) begin
        if(refresh) begin
            if(sel == 2'd2)
                sel <= 0;
            else
                sel <= sel + 1;
        end
    end


    // ==========================
    // SELECCIÓN DE DÍGITO
    // ==========================
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

    assign an = ~(4'b0001 << sel); // activo en bajo

endmodule


