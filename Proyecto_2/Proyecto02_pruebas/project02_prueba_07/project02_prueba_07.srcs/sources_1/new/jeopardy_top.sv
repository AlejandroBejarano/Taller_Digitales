`timescale 1ns / 1ps

module jeopardy_top (
    input  logic        clk,
    input  logic        rst,
    
    // Botones (Pulsadores físicos de la FPGA)
    input  logic        btn_ok,     // START y Confirmar Selección (FPGA)
    input  logic        btn_sel,    // Navegar A->B->C->D
    input  logic        btn_scr,    // Alternar vista Preguntas/Opciones
    
    // Pines UART Pmod/USB
    input  logic        rx,
    output logic        tx,
    
    // Pines PmodCLP LCD (HD44780)
    output logic        lcd_rs,
    output logic        lcd_rw,
    output logic        lcd_e,
    output logic [7:0]  lcd_d,
    
    // Displays de 7-Segmentos
    output logic [6:0]  seg,
    output logic [3:0]  an,
    output logic        dp,
    
    // Zumbador (Pmod)
    output logic        buzzer
);

    // =====================================================================
    // Clock generator (16 MHz) y Debouncers
    // =====================================================================
    logic clk_16MHz;
    logic rst_db;
    logic ok_db;
    logic sel_db;
    logic scr_db;

    clk_wiz_0 clk_wiz_inst (
        .clk_out1(clk_16MHz),
        .reset(rst),
        .locked(),
        .clk_in1(clk)
    );

    debouncer db_rst (
        .clk(clk_16MHz), .reset(1'b0), .btn_in(rst), .btn_out(rst_db)
    );
    debouncer db_ok (
        .clk(clk_16MHz), .reset(rst_db), .btn_in(btn_ok), .btn_out(ok_db)
    );
    debouncer db_sel (
        .clk(clk_16MHz), .reset(rst_db), .btn_in(btn_sel), .btn_out(sel_db)
    );
    debouncer db_scr (
        .clk(clk_16MHz), .reset(rst_db), .btn_in(btn_scr), .btn_out(scr_db)
    );

    // =====================================================================
    // Interconexión (Cables internos)
    // =====================================================================
    logic       fpga_ans_valid;
    logic       fpga_ans_correct;
    logic       pc_ans_valid;
    logic       pc_ans_correct;
    
    logic       enable_lcd;
    logic       enable_uart;
    logic [3:0] question_idx;
    
    logic       play_ok;
    logic       play_error;
    
    logic [5:0] timer_val;
    logic [3:0] scoreA;
    logic [3:0] scoreB;

    // =====================================================================
    // Unidad de Control (FSM Maestra y Temporizadores)
    // =====================================================================
    CU_top u_control (
        .clk_16MHz          (clk_16MHz),
        .rst                (rst_db),
        .btn_ok_i           (ok_db),
        
        // Entradas de respuesta validada
        .fpga_ans_valid_i   (fpga_ans_valid),
        .fpga_ans_correct_i (fpga_ans_correct),
        .pc_ans_valid_i     (pc_ans_valid),
        .pc_ans_correct_i   (pc_ans_correct),
        
        // Salidas de mando
        .lcd_enable_o       (enable_lcd),
        .uart_enable_o      (enable_uart),
        .question_idx_o     (question_idx),
        .play_ok_o          (play_ok),
        .play_error_o       (play_error),
        .timer_val_o        (timer_val),
        .scoreA_o           (scoreA),
        .scoreB_o           (scoreB)
    );

    // =====================================================================
    // Interface de Periféricos (ROMs, LCD, UART, Audio, 7Seg)
    // =====================================================================
    peripheral_top u_peripherals (
        .clk_16MHz          (clk_16MHz),
        .rst                (rst_db),
        
        // Comandos de Control
        .enable_lcd_i       (enable_lcd),
        .enable_uart_i      (enable_uart),
        .question_idx_i     (question_idx),
        .timer_val_i        (timer_val),
        .scoreA_i           (scoreA),
        .scoreB_i           (scoreB),
        .play_ok_i          (play_ok),
        .play_error_i       (play_error),
        
        // Botones
        .btn_scr_i          (scr_db),
        .btn_sel_i          (sel_db),
        .btn_ok_i           (ok_db),
        
        // Retorno de evento de respuesta
        .fpga_ans_valid_o   (fpga_ans_valid),
        .fpga_ans_correct_o (fpga_ans_correct),
        .pc_ans_valid_o     (pc_ans_valid),
        .pc_ans_correct_o   (pc_ans_correct),
        
        // Hardware I/O
        .rx                 (rx),
        .tx                 (tx),
        .lcd_rs             (lcd_rs),
        .lcd_rw             (lcd_rw),
        .lcd_e              (lcd_e),
        .lcd_d              (lcd_d),
        .seg                (seg),
        .an                 (an),
        .dp                 (dp),
        .buzzer_pin         (buzzer)
    );

endmodule
