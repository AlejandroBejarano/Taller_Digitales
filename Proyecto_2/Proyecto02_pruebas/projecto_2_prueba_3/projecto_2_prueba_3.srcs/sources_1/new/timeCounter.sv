module timeCounter(
    input  logic clk,
    input  logic rst,
    input logic rst_i, //30 seconds pulse
    input logic tA,
    input logic tB,
    output logic time_tie,
    output logic tA_1,
    output logic tB_1
);

    logic [31:0] counterA;
    logic [31:0] counterB;
    logic lockedA;
    logic lockedB;

    // Count cycles from rst until player A buzzes
    always_ff @(posedge clk or posedge rst) begin
        if (rst || rst_i) begin
            counterA <= 0;
            lockedA  <= 0;
        end else if (tA && !lockedA) begin
            lockedA  <= 1;  // freeze counter when A buzzes
        end else if (!lockedA) begin
            counterA <= counterA + 1;
        end
    end

    // Count cycles from rst until player B buzzes
    always_ff @(posedge clk or posedge rst) begin
        if (rst || rst_i) begin
            counterB <= 0;
            lockedB  <= 0;
        end else if (tB && !lockedB) begin
            lockedB  <= 1;  // freeze counter when B buzzes
        end else if (!lockedB) begin
            counterB <= counterB + 1;
        end
    end

    // Compare once both have buzzed
    always_comb begin
        tA_1     = 0;
        tB_1     = 0;
        time_tie = 0;
        if (lockedA && lockedB) begin
            if (counterA < counterB)
                tA_1 = 1;       // A buzzed first
            else if (counterB < counterA)
                tB_1 = 1;       // B buzzed first
            else
                time_tie = 1;   // same cycle, tie
        end
    end

endmodule
