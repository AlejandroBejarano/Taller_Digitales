`timescale 1ns / 1ps


module rom_model (
    input  logic       clka,
    input  logic [8:0] addra,
    output logic [7:0] douta
);
    logic [7:0] mem [0:319];

    initial begin
        // Pregunta 0: (x+2)^2
        mem[  0] = 8'h28; mem[  1] = 8'h78; mem[  2] = 8'h2B; mem[  3] = 8'h32;
        mem[  4] = 8'h29; mem[  5] = 8'h5E; mem[  6] = 8'h32; mem[  7] = 8'h20;
        for (int i=8; i<32; i++) mem[i] = 8'h20;
        // Pregunta 1: 5*(x+3)^2
        mem[ 32] = 8'h35; mem[ 33] = 8'h2A; mem[ 34] = 8'h28; mem[ 35] = 8'h78;
        mem[ 36] = 8'h2B; mem[ 37] = 8'h33; mem[ 38] = 8'h29; mem[ 39] = 8'h5E;
        mem[ 40] = 8'h32; for (int i=41; i<64; i++) mem[i] = 8'h20;
        // Resto relleno con espacios
        for (int i=64; i<320; i++) mem[i] = 8'h20;
    end

    // Latencia de 2 ciclos (simula BRAM con registro de salida)
    logic [7:0] stage1;
    always_ff @(posedge clka) begin
        stage1 <= mem[addra];
        douta  <= stage1;
    end
endmodule