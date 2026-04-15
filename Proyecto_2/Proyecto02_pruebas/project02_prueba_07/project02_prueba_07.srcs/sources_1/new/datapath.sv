// =============================================================================
// datapath.sv — Colección de módulos de control y juego para Jeopardy
// =============================================================================
`timescale 1ns / 1ps

module LFSR #(parameter NUM_BITS = 4) (
   input  logic clk,
   input  logic rst,
   input  logic enable,
   input  logic [NUM_BITS-1:0] i_Seed_Data,
   output logic [NUM_BITS-1:0] o_LFSR_Data,
   output logic o_LFSR_Done
);
  logic [NUM_BITS:1] r_LFSR;
  logic              r_XNOR;

  always_ff @(posedge clk) begin
    if (rst) begin
        r_LFSR <= i_Seed_Data;
    end else if (enable == 1'b1) begin
        r_LFSR <= {r_LFSR[NUM_BITS-1:1], r_XNOR};
    end
  end
 
  always_comb begin
      case (NUM_BITS)
        4: r_XNOR = r_LFSR[4] ^~ r_LFSR[3];
        default: r_XNOR = 0; 
      endcase
  end
 
  assign o_LFSR_Data = r_LFSR[NUM_BITS:1];
  assign o_LFSR_Done = (r_LFSR[NUM_BITS:1] == i_Seed_Data) ? 1'b1 : 1'b0;
endmodule

module thirty_sec_timer(
    input  logic clk,
    input  logic rst,
    input  logic enable_i,
    output logic rst_i //30 seconds pulse
);
    // Para 16 MHz y 30 segundos = 480,000,000 ciclos
    localparam int CNT_MAX = (16_000_000 * 30) - 1;
    logic [28:0] counter;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= 0;
            rst_i   <= 0;
        end else begin
            if (enable_i) begin
                if (counter == CNT_MAX) begin
                    counter <= 0;
                    rst_i   <= 1;
                end else begin
                    counter <= counter + 1;
                    rst_i   <= 0;
                end
            end else begin
                counter <= 0;
                rst_i   <= 0;
            end
        end
    end
endmodule

module timeCounter(
    input  logic clk,
    input  logic rst,
    input  logic rst_i, 
    input  logic tA,
    input  logic tB,
    output logic time_tie,
    output logic tA_1,
    output logic tB_1
);
    logic [31:0] counterA;
    logic [31:0] counterB;
    logic lockedA, lockedB;

    always_ff @(posedge clk or posedge rst) begin
        if (rst || rst_i) begin
            counterA <= 0;
            lockedA  <= 0;
        end else if (tA && !lockedA) begin
            lockedA  <= 1;
        end else if (!lockedA) begin
            counterA <= counterA + 1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst || rst_i) begin
            counterB <= 0;
            lockedB  <= 0;
        end else if (tB && !lockedB) begin
            lockedB  <= 1;
        end else if (!lockedB) begin
            counterB <= counterB + 1;
        end
    end

    always_comb begin
        tA_1     = 0;
        tB_1     = 0;
        time_tie = 0;
        if (lockedA && lockedB) begin
            if (counterA < counterB)
                tA_1 = 1;
            else if (counterB < counterA)
                tB_1 = 1;
            else
                time_tie = 1;
        end else if (lockedA) begin
            tA_1 = 1;
        end else if (lockedB) begin
            tB_1 = 1;
        end
    end
endmodule

module random_number (
    input  logic clk,
    input  logic rst,
    input  logic enable,
    input  logic [3:0] lfsr_out,
    output logic [3:0] number,
    output logic valid
);
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            number <= 4'd1;
            valid  <= 0;
        end else if (enable) begin
            valid <= 0;
            // Solo dejamos pasar de 0 a 9 (índices válidos para memoria)
            if (lfsr_out <= 4'd9) begin
                number <= lfsr_out;
                valid  <= 1;
            end
        end
    end
endmodule

module question_selector (
    input  logic clk,
    input  logic rst,
    input  logic enable,
    input  logic [3:0] number,
    input  logic       valid,

    output logic [3:0] question_index,
    output logic ready,
    output logic round_done      // high when 7 questions have been picked
);
    logic [9:0] used_mask;
    logic [2:0] pick_count;      

    assign round_done = (pick_count == 7);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            question_index <= 0;
            ready          <= 0;
            used_mask      <= 10'b0;
            pick_count     <= 0;
        end else begin
            ready <= 0;
            if (enable && valid && !round_done) begin
                if (!used_mask[number]) begin
                    used_mask[number] <= 1;
                    question_index    <= number;
                    ready             <= 1;
                    pick_count        <= pick_count + 1;
                end
            end
        end
    end
endmodule
