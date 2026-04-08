module random_number (
    input  logic clk,
    input  logic rst,
    input  logic enable,
    output logic [3:0] number,
    output logic valid
);

    logic [3:0] lfsr_out;

    // Instantiate your LFSR
    LFSR #(4) lfsr_inst (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .i_Seed_Data(4'b1011),
        .o_LFSR_Data(lfsr_out),
        .o_LFSR_Done()
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            number <= 4'd1;
            valid  <= 0;
        end else if (enable) begin
            valid <= 0;

            if (lfsr_out >= 1 && lfsr_out <= 10) begin
                number <= lfsr_out;
                valid  <= 1;
            end
        end
    end

endmodule