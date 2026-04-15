`timescale 1ns / 1ps

module uart_interface (
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic        we_i,
    input  logic [1:0]  addr_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    input  logic        rx,
    output logic        tx
);
    logic        tx_rdy, tx_start, send_pending, new_rx_flag;
    logic [7:0]  tx_reg, rx_reg, rx_data;
    logic        next_send_pending, next_new_rx_flag, uart_rx_rdy;
 
    logic        tx_rdy_reg, tx_rdy_clean;
    logic [2:0]  rst_guard;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            tx_rdy_reg <= 1'b0;
            rst_guard  <= 3'd0;
        end else begin
            tx_rdy_reg <= tx_rdy;
            if (rst_guard != 3'd7) rst_guard <= rst_guard + 3'd1;
        end
    end
 
    assign tx_rdy_clean = (rst_guard == 3'd7) ? tx_rdy_reg : 1'b0;
 
    always_comb begin
        case (addr_i)
            2'b00:   rdata_o = {30'b0, new_rx_flag, send_pending};
            2'b11:   rdata_o = {24'b0, rx_reg};
            default: rdata_o = 32'b0;
        endcase
    end
 
    always_comb begin
        next_send_pending = send_pending;
        next_new_rx_flag  = new_rx_flag;
 
        if (we_i && addr_i == 2'b00) begin
            if ( wdata_i[0]) next_send_pending = 1'b1;
            if (!wdata_i[1]) next_new_rx_flag  = 1'b0;
        end
        if (uart_rx_rdy) next_new_rx_flag = 1'b1;
        if (tx_rdy_clean && send_pending) next_send_pending = 1'b0;
    end
 
    logic send_pending_prev;
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            tx_reg <= 8'h00; rx_reg <= 8'h00;
            send_pending <= 1'b0; new_rx_flag <= 1'b0;
            tx_start <= 1'b0; send_pending_prev <= 1'b0;
        end else begin
            if (we_i && addr_i == 2'b10) tx_reg <= wdata_i[7:0];
            if (uart_rx_rdy) rx_reg <= rx_data;
            
            send_pending <= next_send_pending;
            new_rx_flag  <= next_new_rx_flag;
            send_pending_prev <= send_pending;
            tx_start <= next_send_pending & ~send_pending;
        end
    end
 
    UART uart_inst (
        .clk         (clk_i),
        .reset       (rst_i),
        .tx_start    (tx_start),
        .tx_rdy      (tx_rdy),
        .data_in     (tx_reg),
        .rx_data_rdy (uart_rx_rdy),
        .data_out    (rx_data),
        .rx          (rx),
        .tx          (tx)
    );
endmodule
