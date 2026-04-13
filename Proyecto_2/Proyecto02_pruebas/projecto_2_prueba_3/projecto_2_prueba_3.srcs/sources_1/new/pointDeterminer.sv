module pointDeterminer(
    input logic clk,
    input logic rst,
    input logic rst_i,
    input logic responseP1,
    input logic responseP2, 
    input logic pt,
    input logic playerA_first,
    input logic playerB_first,
    input logic both_first,
    output logic [3:0] scoreA,
    output logic [3:0] scoreB
);

    always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        scoreA <= 0;
        scoreB <= 0;
    end else if (pt) begin
        if (both_first) begin
            if (responseP1)
                scoreA <= scoreA + 1;
        end else if (playerA_first && responseP1) begin
            scoreA <= scoreA + 1;
        end else if (playerB_first && responseP2) begin
            scoreB <= scoreB + 1;
        end
    end
    end

endmodule