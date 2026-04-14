`timescale 1ns / 1ps
// =============================================================================
// Modulo  : peripheral_top.sv
// Integra todo el datapath y expone las señales a la maquina de control principal
// =============================================================================
module peripheral_top #(
    parameter int MSG_LEN  = 32,
    parameter int SIM_FAST = 0
)(
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic        uart_start_tx_i,
    input  logic [31:0] uart_base_addr_i,
    output logic        uart_tx_done_o,
    output logic        uart_rx_done_o,
    output logic [7:0]  uart_rx_data_o,
    input  logic        lcd_we_i,
    input  logic [1:0]  lcd_addr_i,
    input  logic [31:0] lcd_wdata_i,
    output logic [31:0] lcd_rdata_o,
    output logic [7:0]  lcd_option_byte_o,
    input  logic [5:0]  timer_i,
    input  logic [3:0]  score_fpga_i,
    input  logic [3:0]  score_pc_i,
    input  logic        play_ok_i,
    input  logic        play_error_i,
    input  logic        rx,
    output logic        tx,
    output logic        lcd_rs,
    output logic        lcd_rw,
    output logic        lcd_e,
    output logic [7:0]  lcd_d,
    output logic [6:0]  seg_o,
    output logic [3:0]  an_o,
    output logic        dp_o,
    output logic        buzzer_pin
);

    localparam int LCD_POWERON_US = (SIM_FAST == 1) ? 100 : 50_000;

    logic [31:0] uart_rom_addr;
    logic [7:0]  uart_rom_data;
    logic [3:0]  rom_question_num;
    logic [4:0]  rom_question_off;
    logic [7:0]  lcd_question_byte;

    assign rom_question_num = uart_rom_addr[8:5];
    assign rom_question_off = uart_rom_addr[4:0];
    assign uart_rom_data    = lcd_question_byte;

    // -------------------------------------------------------------------------
    // UART System
    // -------------------------------------------------------------------------
    uart_system #(
        .MSG_LEN(MSG_LEN)
    ) u_uart (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .start_tx_i  (uart_start_tx_i),
        .base_addr_i (uart_base_addr_i),
        .tx_done_o   (uart_tx_done_o),
        .rx_done_o   (uart_rx_done_o),
        .rx_data_o   (uart_rx_data_o),
        .rom_addr_o  (uart_rom_addr),
        .rom_data_i  (uart_rom_data),
        .rx          (rx),
        .tx          (tx)
    );

    // -------------------------------------------------------------------------
    // LCD Peripheral (incluye ROMs de preguntas y opciones)
    // -------------------------------------------------------------------------
    lcd_peripheral #(
        .POWERON_US(LCD_POWERON_US)
    ) u_lcd (
        .clk_i          (clk_i),
        .rst_i          (rst_i),
        .write_enable_i (lcd_we_i),
        .addr_i         (lcd_addr_i),
        .wdata_i        (lcd_wdata_i),
        .rdata_o        (lcd_rdata_o),
        .lcd_rs         (lcd_rs),
        .lcd_rw         (lcd_rw),
        .lcd_e          (lcd_e),
        .lcd_d          (lcd_d),
        .question_num   (rom_question_num),
        .question_off   (rom_question_off),
        .question_byte_o(lcd_question_byte),
        .option_byte_o  (lcd_option_byte_o)
    );

    // -------------------------------------------------------------------------
    // 7-Segment Display
    // -------------------------------------------------------------------------
    segments u_segments (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .timer_i     (timer_i),
        .score_fpga_i(score_fpga_i),
        .score_pc_i  (score_pc_i),
        .seg_o       (seg_o),
        .an_o        (an_o),
        .dp_o        (dp_o)
    );

    // -------------------------------------------------------------------------
    // Buzzer
    // -------------------------------------------------------------------------
    buzzer u_buzzer (
        .clk    (clk_i),
        .rst    (rst_i),
        .play_ok   (play_ok_i),
        .play_error(play_error_i),
        .buzzer    (buzzer_pin)
    );

endmodule