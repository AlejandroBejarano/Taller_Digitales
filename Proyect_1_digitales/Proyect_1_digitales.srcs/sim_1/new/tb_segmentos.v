`timescale 1ns / 1ps


module tb_segmentos;

    reg  [3:0] bin;
    wire [6:0] seg;

    // Instanciamos el módulo a probar
    segmentos uut (
        .bin(bin),
        .seg(seg)
    );

    initial begin
        
        // Probar todos los valores 0-9
        bin = 4'd0; #10;
        bin = 4'd1; #10;
        bin = 4'd2; #10;
        bin = 4'd3; #10;
        bin = 4'd4; #10;
        bin = 4'd5; #10;
        bin = 4'd6; #10;
        bin = 4'd7; #10;
        bin = 4'd8; #10;
        bin = 4'd9; #10;

        $stop; // detener simulación
    end

endmodule