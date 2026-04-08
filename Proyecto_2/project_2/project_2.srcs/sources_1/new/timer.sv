module timer(
    input  logic clk,
    input  logic rst,
    output logic rst_i //30 seconds pulse
);

    localparam CNT_MAX = 3 - 1;//=clock_frequency*time_in_seconds -1
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
//de momento está en nanosegundos con clock de 100 MHz.
//Para 30 segundos la simulación se vuelve un poco diferente y no he llegado ahí