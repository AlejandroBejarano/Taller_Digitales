// =============================================================================
// peripheral_top.sv — Módulo Integrador de Periféricos (UART, LCD, Segments, Buzzer)
// =============================================================================
`timescale 1ns / 1ps

module peripheral_top (
    input  logic        clk_16MHz,
    input  logic        rst,

    // Comandos desde CU_top
    input  logic        enable_lcd_i,
    input  logic        enable_uart_i,
    input  logic [3:0]  question_idx_i,

    input  logic [5:0]  timer_val_i,
    input  logic [3:0]  scoreA_i,
    input  logic [3:0]  scoreB_i,

    input  logic        play_ok_i,
    input  logic        play_error_i,

    // Botones jugador FPGA (Scroll y Seleccionar Opcion/Cursor)
    input  logic        btn_scr_i,
    input  logic        btn_sel_i,
    input  logic        btn_ok_i,

    // Resultados devueltos hacia CU_top
    output logic        fpga_ans_valid_o,
    output logic        fpga_ans_correct_o,
    output logic        pc_ans_valid_o,
    output logic        pc_ans_correct_o,

    // Pines Físicos
    input  logic        rx,
    output logic        tx,
    output logic        lcd_rs,
    output logic        lcd_rw,
    output logic        lcd_e,
    output logic [7:0]  lcd_d,
    output logic [6:0]  seg,
    output logic [3:0]  an,
    output logic        dp,
    output logic        buzzer_pin
);

    // =========================================================================
    // Block RAMs (ROM Preguntas y Opciones) configuradas a Dual-Port
    // =========================================================================
    logic [8:0] rom_q_addr_uart, rom_q_addr_lcd;
    logic [7:0] rom_q_data_uart, rom_q_data_lcd;
    
    blk_mem_gen_0 rom_preguntas (
        .clka (clk_16MHz),    .ena (1'b1),    
        .addra(rom_q_addr_uart), .douta(rom_q_data_uart),
        
        .clkb (clk_16MHz),    .enb (1'b1),    
        .addrb(rom_q_addr_lcd),  .doutb(rom_q_data_lcd)
    );

    logic [8:0] rom_a_addr_uart, rom_a_addr_lcd;
    logic [7:0] rom_a_data_uart, rom_a_data_lcd;
    
    blk_mem_gen_1 rom_respuestas (
        .clka (clk_16MHz),    .ena (1'b1),    
        .addra(rom_a_addr_uart), .douta(rom_a_data_uart),
        
        .clkb (clk_16MHz),    .enb (1'b1),    
        .addrb(rom_a_addr_lcd),  .doutb(rom_a_data_lcd)
    );

    // =========================================================================
    // UART Subsystem (Jugador PC)
    // =========================================================================
    logic        uart_we;
    logic [1:0]  uart_addr;
    logic [31:0] uart_wdata;
    logic [31:0] uart_rdata;

    uart_interface u_uart (
        .clk_i(clk_16MHz), .rst_i(rst),
        .we_i(uart_we), .addr_i(uart_addr), .wdata_i(uart_wdata), .rdata_o(uart_rdata),
        .rx(rx), .tx(tx)
    );

    logic        tx_fsm_we;
    logic [1:0]  tx_fsm_addr;
    logic [31:0] tx_fsm_wdata;

    uart_tx_fsm u_uart_tx_fsm (
        .clk_i        (clk_16MHz),
        .rst_i        (rst),
        .start_i      (enable_uart_i),      
        .question_idx_i(question_idx_i),   
        .rom_q_addr_o (rom_q_addr_uart),
        .rom_q_data_i (rom_q_data_uart),
        .rom_a_addr_o (rom_a_addr_uart),
        .rom_a_data_i (rom_a_data_uart),
        .uart_we_o    (tx_fsm_we),
        .uart_addr_o  (tx_fsm_addr),
        .uart_wdata_o (tx_fsm_wdata),
        .uart_rdata_i (uart_rdata)         
    );

    logic        chk_we;
    logic [1:0]  chk_addr;
    logic [31:0] chk_wdata;

    answer_checker u_checker_pc (
        .clk_i            (clk_16MHz),
        .rst_i            (rst),
        .enable_i         (1'b1),
        .question_idx_i   (question_idx_i),
        .answer_valid_o   (pc_ans_valid_o),
        .answer_correct_o (pc_ans_correct_o),
        .answer_letter_o  (),
        .answer_invalid_o (),
        .uart_we_o        (chk_we),
        .uart_addr_o      (chk_addr),
        .uart_wdata_o     (chk_wdata),
        .uart_rdata_i     (uart_rdata)
    );

    // Mux UART: Priorizamos TX (tx_fsm) sobre RX (checker)
    always_comb begin
        if (tx_fsm_we) begin
            uart_we    = tx_fsm_we;
            uart_addr  = tx_fsm_addr;
            uart_wdata = tx_fsm_wdata;
        end else begin
            uart_we    = chk_we;
            uart_addr  = chk_addr;
            uart_wdata = chk_wdata;
        end
    end

    // =========================================================================
    // LCD Subsystem (Jugador FPGA)
    // =========================================================================
    logic        lcd_we;
    logic [1:0]  lcd_addr;
    logic [31:0] lcd_wdata;
    logic [31:0] lcd_rdata;

    lcd_peripheral u_lcd (
        .clk_i          (clk_16MHz),
        .rst_i          (rst),
        .write_enable_i (lcd_we),
        .addr_i         (lcd_addr),
        .wdata_i        (lcd_wdata),
        .rdata_o        (lcd_rdata),
        .lcd_rs_o       (lcd_rs),
        .lcd_rw_o       (lcd_rw),
        .lcd_en_o       (lcd_e),
        .lcd_data_o     (lcd_d)
    );

    logic [7:0] lcd_fpga_char;

    lcd_fsm u_lcd_fsm (
        .clk_i               (clk_16MHz),
        .rst_i               (rst),
        .enable_i            (enable_lcd_i),
        .question_idx_i      (question_idx_i),
        .btn_scr_i           (btn_scr_i),
        .btn_sel_i           (btn_sel_i),
        .btn_ok_i            (btn_ok_i),
        .fpga_answer_valid_o (fpga_ans_valid_o),
        .fpga_answer_char_o  (lcd_fpga_char),
        .rom_q_addr_o        (rom_q_addr_lcd),
        .rom_q_data_i        (rom_q_data_lcd),
        .rom_a_addr_o        (rom_a_addr_lcd),
        .rom_a_data_i        (rom_a_data_lcd),
        .lcd_we_o            (lcd_we),
        .lcd_addr_o          (lcd_addr),
        .lcd_wdata_o         (lcd_wdata),
        .lcd_rdata_i         (lcd_rdata)
    );

    // =========================================================================
    // Checker de respuesta FPGA (Combinacional)
    // =========================================================================
    function automatic logic [7:0] get_correct_answer(input logic [3:0] idx);
        case (idx)
            4'd0:    get_correct_answer = 8'h43; // C
            4'd1:    get_correct_answer = 8'h42; // B
            4'd2:    get_correct_answer = 8'h41; // A
            4'd3:    get_correct_answer = 8'h41; // A
            4'd4:    get_correct_answer = 8'h43; // C
            4'd5:    get_correct_answer = 8'h42; // B
            4'd6:    get_correct_answer = 8'h42; // B
            4'd7:    get_correct_answer = 8'h44; // D
            4'd8:    get_correct_answer = 8'h44; // D
            4'd9:    get_correct_answer = 8'h41; // A
            default: get_correct_answer = 8'h00; // Inválido
        endcase
    endfunction

    assign fpga_ans_correct_o = (lcd_fpga_char == get_correct_answer(question_idx_i));

    // =========================================================================
    // Hardware Auxiliar Visual/Sonoro
    // =========================================================================
    segments u_segments (
        .clk_i       (clk_16MHz),
        .rst_i       (rst),
        .timer_i     (timer_val_i),
        .score_fpga_i(scoreA_i),
        .score_pc_i  (scoreB_i),
        .seg_o       (seg),
        .an_o        (an),
        .dp_o        (dp)
    );

    buzzer u_buzzer (
        .clk_i      (clk_16MHz),
        .rst_i      (rst),
        .play_ok_i  (play_ok_i),
        .play_err_i (play_error_i),
        .buzzer_o   (buzzer_pin)
    );

endmodule
