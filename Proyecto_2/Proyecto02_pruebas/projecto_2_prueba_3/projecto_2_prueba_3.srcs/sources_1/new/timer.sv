//CAMBIO: se cambio CNT_MAX de localparam a parameter porque el modulo original
//usaba localparam CNT_MAX = 3-1, lo que hacia que la instancia en top_jeopardy
//con #(.CNT_MAX(480000000)) no tuviera efecto (localparam no es sobreescribible).
//El valor por defecto (3-1=2) mantiene compatibilidad con simulacion rapida.
module timer #(
    parameter int CNT_MAX = 3 - 1 // default: simulacion rapida (3 ciclos)
    // Hardware 30s @ 16MHz: CNT_MAX = 16_000_000*30 - 1 = 479_999_999
)(
    input  logic clk,
    input  logic rst,
    output logic rst_i //30 seconds pulse
);

    logic [32:0] counter;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= 0;
            rst_i <= 0;
        end else begin
            if (counter == CNT_MAX) begin
                counter <= 0;
                rst_i <= 1;
            end else begin
                counter <= counter + 1;
                rst_i <= 0;
            end
        end
    end
endmodule
//Para hardware real usar: CNT_MAX = 16_000_000*30 - 1 (30s @ 16MHz via clk_wiz_0)