`timescale 1ns / 1ps

// =============================================================================
// Módulo  : uart_system (sin cambios - wrapper limpio)
// =============================================================================
module uart_system #(
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
    input  logic        rx,
    output logic        tx
);
    logic        internal_we;
    logic [1:0]  internal_addr;
    logic [31:0] internal_wdata;
    logic [31:0] internal_rdata;
 
    uart_fsm #(
        .MSG_LEN (MSG_LEN)
    ) u_fsm (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .start_tx_i  (start_tx_i),
        .base_addr_i (base_addr_i),
        .tx_done_o   (tx_done_o),
        .rx_done_o   (rx_done_o),
        .rx_data_o   (rx_data_o),
        .rom_addr_o  (rom_addr_o),
        .rom_data_i  (rom_data_i),
        .we_o        (internal_we),
        .addr_o      (internal_addr),
        .wdata_o     (internal_wdata),
        .rdata_i     (internal_rdata)
    );
 
    uart_interface u_interface (
        .clk_i   (clk_i),
        .rst_i   (rst_i),
        .we_i    (internal_we),
        .addr_i  (internal_addr),
        .wdata_i (internal_wdata),
        .rdata_o (internal_rdata),
        .rx      (rx),
        .tx      (tx)
    );
endmodule


