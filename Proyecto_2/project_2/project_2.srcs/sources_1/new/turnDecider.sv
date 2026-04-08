module turnDecider(
    input  logic clk,
    input  logic rst,
    input  logic rst_i,
    input  logic tA_1,
    input  logic tB_1,
    input  logic time_tie,
    output logic no_answer,
    output logic both_first,
    output logic playerA_first,
    output logic playerB_first,
    output logic [3:0] n
);

    // =========================
    // Internal signals
    // =========================
    logic answered;
    logic rst_i_d;
    logic rst_i_posedge;

    // =========================
    // Edge detector for rst_i
    // =========================
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            rst_i_d <= 0;
        else
            rst_i_d <= rst_i;
    end

    assign rst_i_posedge = rst_i & ~rst_i_d;

    // =========================
    // Track if someone answered
    // =========================
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            answered <= 0;
        else if (rst_i_posedge)
            answered <= 0;  // new round
        else if (tA_1 || tB_1 || time_tie)
            answered <= 1;  // someone answered
    end

    // =========================
    // no_answer → 1-cycle pulse
    // =========================
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            no_answer <= 0;
        else begin
            no_answer <= 0;  // default (creates pulse)

            if (rst_i_posedge && !answered)
                no_answer <= 1;
        end
    end

    // =========================
    // Round counter
    // =========================
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            n <= 0;
        else if (rst_i)
            n <= n + 1;
    end

    // =========================
    // Decision logic (who answered first)
    // =========================
    always_ff @(posedge clk or posedge rst or posedge rst_i) begin
        if (rst || rst_i) begin
            playerA_first <= 0;
            playerB_first <= 0;
            both_first    <= 0;
        end else if (!(playerA_first || playerB_first || both_first)) begin
            if (time_tie)
                both_first <= 1;
            else if (tA_1)
                playerA_first <= 1;
            else if (tB_1)
                playerB_first <= 1;
        end
    end

endmodule