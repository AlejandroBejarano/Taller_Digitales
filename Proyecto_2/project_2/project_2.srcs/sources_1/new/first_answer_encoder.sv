module firstAnswerEncoder(
    input  logic no_answer,
    input  logic playerA_first,
    input  logic playerB_first,
    input  logic both_first,
    output logic responseP1,
    output logic responseP2
);

    always_comb begin
        // default
        responseP1 = 0;
        responseP2 = 0;

        if (both_first) begin
            responseP1 = 1;
            responseP2 = 1;
        end else if (playerA_first || playerB_first) begin
            responseP1 = 1;
        end
        // no_answer → both stay 0
    end


    always_ff @(posedge rst_i) begin
        responseP1 <=0;
        responseP2 <=0;
    end


endmodule