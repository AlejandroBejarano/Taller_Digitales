module patternMoore(
    input logic clk,
    input logic rst,
    input logic rst_i,
    input logic responseP1,
    input logic responseP2, 
    output logic pt
);

typedef enum logic [1:0] {
    S0, S1, S2} statetype; //S0, S2, S1
statetype state, nextstate;

//here begins the state register
always_ff @(posedge clk, posedge rst)
    if (rst)    state <= S0;
    else if (rst_i) state <= S0;
    else        state <= nextstate;

//now next state logic
always_comb
    case(state)
        S0: if (responseP1) nextstate = S2;
        else nextstate = S1;
        S1: if (responseP2) nextstate = S2;
        else nextstate = S1;
        default: nextstate = S0;
    endcase

//output logic
    assign pt = (state==S2);
endmodule