`timescale 1ns / 1ps

module segments (
    input  logic        clk_i,         // Reloj del sistema: 16 MHz
    input  logic        rst_i,         // Reset sincrono, activo en alto
    input  logic [5:0]  timer_i,       // Tiempo restante en segundos (0-30)
    input  logic [3:0]  score_fpga_i,  // Puntaje jugador FPGA (0-7)
    input  logic [3:0]  score_pc_i,    // Puntaje jugador PC   (0-7)
    output reg  [6:0]   seg_o,         // Segmentos {g,f,e,d,c,b,a}, activo-bajo
    output reg  [3:0]   an_o,          // Seleccion de anode,         activo-bajo
    output logic        dp_o           // Punto decimal: siempre apagado
);

    assign dp_o = 1'b1; // Punto decimal(apagado)

    localparam integer MUX_DIV = 4000; // 16 MHz / 4000 = 4000 Hz → ~1 kHz refresco por dígito

    reg [11:0] mux_cnt;
    reg [1:0]  digit_sel;

    // Descomposición BCD del timer (0-30)
    logic [5:0] timer_safe;
    logic [3:0] timer_tens;
    logic [5:0] timer_remainder;
    logic [3:0] timer_units;

    assign timer_safe      = (timer_i > 6'd30) ? 6'd30 : timer_i;

    assign timer_tens      = (timer_safe >= 6'd20) ? 4'd2 :
                             (timer_safe >= 6'd10) ? 4'd1 : 4'd0;

    assign timer_remainder = (timer_tens == 4'd2) ? 6'd20 :
                             (timer_tens == 4'd1) ? 6'd10 : 6'd0;

    assign timer_units     = timer_safe - timer_remainder;

    // MUX: selecciona el dígito activo para enviarlo al decodificador
    logic [3:0] digit_to_display;

    always @(*) begin
        case (digit_sel)
            2'd3: digit_to_display = timer_tens;   // AN[3]: decenas del timer
            2'd2: digit_to_display = timer_units;  // AN[2]: unidades del timer
            2'd1: digit_to_display = score_fpga_i; // AN[1]: puntaje FPGA
            2'd0: digit_to_display = score_pc_i;   // AN[0]: puntaje PC
            default: digit_to_display = 4'd15;     // Apagado
        endcase
    end


    // Decodificador de 7 segmentos (activo-bajo)
    logic [6:0] seg;

    always @(*) begin
        case (digit_to_display)
            4'd0: seg = 7'b0000001;
            4'd1: seg = 7'b1001111;
            4'd2: seg = 7'b0010010;
            4'd3: seg = 7'b0000110;
            4'd4: seg = 7'b1001100;
            4'd5: seg = 7'b0100100;
            4'd6: seg = 7'b0100000;
            4'd7: seg = 7'b0001111;
            4'd8: seg = 7'b0000000;
            4'd9: seg = 7'b0000100;
            default: seg = 7'b1111111; // Apaga el display
        endcase
    end

    // Contador de multiplexeo
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            mux_cnt   <= 12'd0;
            digit_sel <= 2'd3;
        end else begin
            if (mux_cnt == MUX_DIV - 1) begin
                mux_cnt   <= 12'd0;
                digit_sel <= digit_sel - 2'd1; // Ciclo: 3→2→1→0→3→...
            end else begin
                mux_cnt <= mux_cnt + 12'd1;
            end
        end
    end

    // Registro de salida: anode + segmentos
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            seg_o <= 7'b1111111;
            an_o  <= 4'b1111;
        end else begin
            seg_o <= seg; // Salida del decodificador
            case (digit_sel)
                2'd3: an_o <= 4'b0111; // Habilita AN[3]
                2'd2: an_o <= 4'b1011; // Habilita AN[2]
                2'd1: an_o <= 4'b1101; // Habilita AN[1]
                2'd0: an_o <= 4'b1110; // Habilita AN[0]
                default: an_o <= 4'b1111;
            endcase
        end
    end

endmodule