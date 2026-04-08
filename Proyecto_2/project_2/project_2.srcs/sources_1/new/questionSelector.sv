module question_selector (
    input  logic clk,
    input  logic rst,
    input  logic enable,

    output logic [3:0] question_index,
    output logic ready,
    output logic round_done      // high when 7 questions have been picked
);

    logic [3:0] random_num;
    logic valid;
    logic [9:0] used_mask;
    logic [2:0] pick_count;      // counts 0-7, only needs 3 bits

    random_number rng (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .number(random_num),
        .valid(valid)
    );

    logic [3:0] candidate;
    assign candidate = random_num - 1;

    assign round_done = (pick_count == 7);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            question_index <= 0;
            ready          <= 0;
            used_mask      <= 10'b0;
            pick_count     <= 0;
        end else begin
            ready <= 0;

            if (valid && !round_done) begin
                if (!used_mask[candidate]) begin
                    used_mask[candidate] <= 1;
                    question_index       <= candidate;
                    ready                <= 1;
                    pick_count           <= pick_count + 1;
                end
            end
        end
    end

endmodule