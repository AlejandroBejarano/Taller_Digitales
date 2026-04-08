module answer_checker (
    input  logic       clk,
    input  logic       rst,
    input  logic [3:0] question_index,
    input  logic [1:0] answer_p1,
    input  logic [1:0] answer_p2,
    input  logic       tA,
    input  logic       tB,

    output logic       responseP1,
    output logic       responseP2
);

    // ROM hardcoded as localparam — synthesises as LUTs, no file needed
    // 00=A  01=B  10=C  11=D
    localparam logic [1:0] answer_table [0:9] = '{
        2'b10,  // Q0 = C
        2'b00,  // Q1 = A
        2'b11,  // Q2 = D
        2'b11,  // Q3 = D
        2'b01,  // Q4 = B
        2'b10,  // Q5 = C
        2'b00,  // Q6 = A
        2'b11,  // Q7 = D
        2'b01,  // Q8 = B
        2'b10   // Q9 = C
    };

    logic [1:0] correct_answer;
    assign correct_answer = answer_table[question_index];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            responseP1 <= 0;
            responseP2 <= 0;
        end else begin
            if (tA)
                responseP1 <= (answer_p1 == correct_answer);
            if (tB)
                responseP2 <= (answer_p2 == correct_answer);
        end
    end

endmodule