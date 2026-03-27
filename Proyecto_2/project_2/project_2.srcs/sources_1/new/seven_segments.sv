`timescale 1ns / 1ps

module segments (
    input  logic        clk_i,         // Reloj del sistema: 16 MHz
    input  logic        rst_i,         // Reset sincrono, activo en alto
    input  logic [5:0]  timer_i,       // Tiempo restante en segundos (0-30)
    input  logic [3:0]  score_fpga_i,  // Puntaje jugador FPGA (0-7)
    input  logic [3:0]  score_pc_i,    // Puntaje jugador PC   (0-7)
    output reg  [6:0]  seg_o,         // Segmentos {g,f,e,d,c,b,a}, activo-bajo
    output reg  [3:0]  an_o,          // Seleccion de anode,         activo-bajo
    output logic        dp_o           // Punto decimal: siempre apagado
);
    assign dp_o = 1'b1; //Punto decimnal en alto (apagado)

    localparam integer MUX_DIV = 4000; // 16 000 000 / 4000 = 4000 Hz , 1 k Hz de refresco

    reg [11:0] mux_cnt;    // Contador de division (2^12 = 4096 > 4000)
    reg [1:0]  digit_sel;  // Digito activo: 3=AN3 ... 0=AN0

    // -------------------------------------------------------------------------
    // Descomposicion BCD del timer (0-30)
    // -------------------------------------------------------------------------
    logic [5:0] timer_safe;     // Timer acotado a [0,30]
    logic [3:0] timer_tens;     // Decenas del timer
    logic [5:0] timer_remainder;// Auxiliar para calcular unidades
    logic [3:0] timer_units;    // Unidades del timer

    assign timer_safe      = (timer_i > 6'd30) ? 6'd30 : timer_i;

    assign timer_tens      = (timer_safe >= 6'd20) ? 4'd2 :
                             (timer_safe >= 6'd10) ? 4'd1 : 4'd0;

    assign timer_remainder = (timer_tens == 4'd2) ? 6'd20 :
                             (timer_tens == 4'd1) ? 6'd10 : 6'd0;

    assign timer_units     = timer_safe - timer_remainder;

    // -- Digito AN[3]: decenas del timer (solo 0, 1, 2) --
    logic [6:0] seg_tens;
    assign seg_tens = (timer_tens == 4'd0) ? 7'b1000000 :
                      (timer_tens == 4'd1) ? 7'b1111001 :
                      (timer_tens == 4'd2) ? 7'b0100100 :
                                             7'b1111111;  // default: apagado

    // -- Digito AN[2]: unidades del timer (0-9) --
    logic [6:0] seg_units;
    assign seg_units = (timer_units == 4'd0) ? 7'b1000000 :
                       (timer_units == 4'd1) ? 7'b1111001 :
                       (timer_units == 4'd2) ? 7'b0100100 :
                       (timer_units == 4'd3) ? 7'b0110000 :
                       (timer_units == 4'd4) ? 7'b0011001 :
                       (timer_units == 4'd5) ? 7'b0010010 :
                       (timer_units == 4'd6) ? 7'b0000010 :
                       (timer_units == 4'd7) ? 7'b1111000 :
                       (timer_units == 4'd8) ? 7'b0000000 :
                       (timer_units == 4'd9) ? 7'b0010000 :
                                               7'b1111111;  // default: apagado

    // -- Digito AN[1]: puntaje jugador FPGA (0-7) --
    logic [6:0] seg_fpga;
    assign seg_fpga = (score_fpga_i == 4'd0) ? 7'b1000000 :
                      (score_fpga_i == 4'd1) ? 7'b1111001 :
                      (score_fpga_i == 4'd2) ? 7'b0100100 :
                      (score_fpga_i == 4'd3) ? 7'b0110000 :
                      (score_fpga_i == 4'd4) ? 7'b0011001 :
                      (score_fpga_i == 4'd5) ? 7'b0010010 :
                      (score_fpga_i == 4'd6) ? 7'b0000010 :
                      (score_fpga_i == 4'd7) ? 7'b1111000 :
                                               7'b1111111;  // default: apagado

    // -- Digito AN[0]: puntaje jugador PC (0-7) --
    logic [6:0] seg_pc;
    assign seg_pc  = (score_pc_i == 4'd0) ? 7'b1000000 :
                     (score_pc_i == 4'd1) ? 7'b1111001 :
                     (score_pc_i == 4'd2) ? 7'b0100100 :
                     (score_pc_i == 4'd3) ? 7'b0110000 :
                     (score_pc_i == 4'd4) ? 7'b0011001 :
                     (score_pc_i == 4'd5) ? 7'b0010010 :
                     (score_pc_i == 4'd6) ? 7'b0000010 :
                     (score_pc_i == 4'd7) ? 7'b1111000 :
                                            7'b1111111;  // default: apagado

    // -------------------------------------------------------------------------
    // Contador de multiplexeo (secuencial)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            mux_cnt   <= 12'd0;
            digit_sel <= 2'd3;  // Comienza en el digito mas significativo
        end else begin
            if (mux_cnt == MUX_DIV - 1) begin
                mux_cnt   <= 12'd0;
                digit_sel <= digit_sel - 2'd1;  // Ciclo: 3->2->1->0->3->...
            end else begin
                mux_cnt <= mux_cnt + 12'd1;
            end
        end
    end


    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            seg_o <= 7'b1111111;  // Todos los segmentos apagados
            an_o  <= 4'b1111;     // Todos los anodes deshabilitados
        end else begin
            case (digit_sel)
                2'd3: begin
                    an_o  <= 4'b0111;   // Habilita AN[3]
                    seg_o <= seg_tens;  // Decenas del timer
                end
                2'd2: begin
                    an_o  <= 4'b1011;   // Habilita AN[2]
                    seg_o <= seg_units; // Unidades del timer
                end
                2'd1: begin
                    an_o  <= 4'b1101;   // Habilita AN[1]
                    seg_o <= seg_fpga;  // Puntaje jugador FPGA
                end
                2'd0: begin
                    an_o  <= 4'b1110;   // Habilita AN[0]
                    seg_o <= seg_pc;    // Puntaje jugador PC
                end
                default: begin
                    an_o  <= 4'b1111;
                    seg_o <= 7'b1111111;
                end
            endcase
        end
    end

endmodule