`timescale 1ns / 1ps

module uart_fsm #(
    parameter int MSG_LEN = 32
) (
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic        start_tx_i,
    input  logic [31:0] base_addr_i,
    output logic        tx_done_o,
    output logic        rx_done_o,
    output logic [7:0]  rx_data_o,
    output logic [31:0] rom_addr_o,
    input  logic [7:0]  rom_data_i,
    output logic        we_o,
    output logic [1:0]  addr_o,
    output logic [31:0] wdata_o,
    input  logic [31:0] rdata_i
);
    localparam int CNT_W = $clog2(MSG_LEN);
 
    typedef enum logic [3:0] {
        IDLE      = 4'd0, TX_FETCH  = 4'd1, TX_LOAD   = 4'd2,
        TX_START  = 4'd3, TX_WAIT   = 4'd4, TX_DONE   = 4'd5,
        RX_WAIT   = 4'd6, RX_READ   = 4'd7, RX_CLEAR  = 4'd8,
        DONE      = 4'd9, TX_ADDR   = 4'd10, TX_FETCH2 = 4'd11
    } state_t;
 
    state_t current_state, next_state;
    logic [CNT_W-1:0] char_counter;
    logic              inc_counter, clr_counter;
 
    always_ff @(posedge clk_i) begin
        if (rst_i) current_state <= IDLE;
        else       current_state <= next_state;
    end
 
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE:      if (start_tx_i) next_state = TX_ADDR;
            TX_ADDR:   next_state = TX_FETCH;
            TX_FETCH:  next_state = TX_FETCH2;
            TX_FETCH2: next_state = TX_LOAD;
            TX_LOAD:   next_state = TX_START;
            TX_START:  next_state = TX_WAIT;
            TX_WAIT:   if (rdata_i[0] == 1'b0) begin
                           if (char_counter == CNT_W'(MSG_LEN - 1)) next_state = TX_DONE;
                           else next_state = TX_ADDR;
                       end
            TX_DONE:   next_state = RX_WAIT;
            RX_WAIT:   if (rdata_i[1] == 1'b1) next_state = RX_READ;
            RX_READ:   next_state = RX_CLEAR;
            RX_CLEAR:  next_state = DONE;
            DONE:      next_state = IDLE;
            default:   next_state = IDLE;
        endcase
    end
 
    always_comb begin
        we_o = 1'b0; addr_o = 2'b00; wdata_o = 32'd0; clr_counter = 1'b0;
        tx_done_o = 1'b0; rx_done_o = 1'b0;
        case (current_state)
            IDLE:     clr_counter = 1'b1;
            TX_LOAD:  begin we_o = 1'b1; addr_o = 2'b10; wdata_o = {24'd0, rom_data_i}; end
            TX_START: begin we_o = 1'b1; addr_o = 2'b00; wdata_o = 32'h0000_0001; end
            TX_DONE:  tx_done_o = 1'b1;
            RX_READ:  addr_o = 2'b11;
            RX_CLEAR: begin we_o = 1'b1; addr_o = 2'b00; wdata_o = 32'h0000_0000; end
            DONE:     rx_done_o = 1'b1;
            default: ;
        endcase
    end
 
    always_ff @(posedge clk_i) begin
        if (rst_i) rom_addr_o <= 32'd0;
        else if (current_state == IDLE && start_tx_i) rom_addr_o <= base_addr_i;
        else if (inc_counter) rom_addr_o <= rom_addr_o + 1'b1;
    end
 
    always_comb begin
        inc_counter = (current_state == TX_WAIT) && (rdata_i[0] == 1'b0) && (char_counter != CNT_W'(MSG_LEN - 1));
    end
 
    always_ff @(posedge clk_i) begin
        if (rst_i || clr_counter) char_counter <= '0;
        else if (inc_counter) char_counter <= char_counter + 1'b1;
    end
 
    always_ff @(posedge clk_i) begin
        if (rst_i) rx_data_o <= 8'd0;
        else if (current_state == RX_READ) rx_data_o <= rdata_i[7:0];
    end
endmodule
 