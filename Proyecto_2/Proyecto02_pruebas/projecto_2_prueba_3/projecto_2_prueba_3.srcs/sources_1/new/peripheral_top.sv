`timescale 1ns / 1ps
// =============================================================================
// Módulo  : peripheral_top
// Función : Integra todos los periféricos del sistema Jeopardy. 
//           Expone interfaces limpias hacia el Control Principal del Juego 
//           y conecta los pines físicos hacia el exterior de la FPGA.
// =============================================================================

module peripheral_top #(
    parameter int MSG_LEN = 32
)(
    // Reloj y Reset Global
    input  logic        clk_i,          // Reloj de 16 MHz
    input  logic        rst_i,          // Reset síncrono activo alto

    // =========================================================================
    // Interfaz hacia la Unidad de Control Principal del Juego
    // =========================================================================
    
    // 1. Control UART (Envío y recepción de datos a PC)
    input  logic        uart_start_tx_i,
    input  logic [31:0] uart_base_addr_i,
    output logic        uart_tx_done_o,
    output logic        uart_rx_done_o,
    output logic [7:0]  uart_rx_data_o,

    // 2. Control LCD (Interfaz Estándar de 32 bits)
    input  logic        lcd_we_i,
    input  logic [1:0]  lcd_addr_i,
    input  logic [31:0] lcd_wdata_i,
    output logic [31:0] lcd_rdata_o,
    
    // Puertos opcionales de lectura de opciones (para lógica de juego si se requiere)
    output logic [7:0]  lcd_option_byte_o,

    // 3. Control Segmentos (Marcadores y Temporizador)
    input  logic [5:0]  timer_i,
    input  logic [3:0]  score_fpga_i,
    input  logic [3:0]  score_pc_i,

    // 4. Control Buzzer (Efectos de sonido)
    input  logic        play_ok_i,
    input  logic        play_error_i,

    // =========================================================================
    // Pines Físicos (Hacia la FPGA Basys3 / Dispositivos externos)
    // =========================================================================
    
    // UART
    input  logic        rx,
    output logic        tx,

    // LCD PmodCLP
    output logic        lcd_rs,
    output logic        lcd_rw,
    output logic        lcd_e,
    output logic [7:0]  lcd_d,

    // 7 Segmentos
    output logic [6:0]  seg_o,
    output logic [3:0]  an_o,
    output logic        dp_o,

    // Buzzer
    output logic        buzzer_pin
);

    // =========================================================================
    // Enrutamiento Interno (Datapath compartido: UART -> ROM de LCD)
    // =========================================================================
    logic [31:0] uart_rom_addr;
    logic [7:0]  uart_rom_data;
    
    logic [3:0]  rom_question_num;
    logic [4:0]  rom_question_off;
    logic [7:0]  lcd_question_byte;

    // Decodificación de dirección lineal de UART a formato segmentado de LCD ROM
    // Asumiendo cada pregunta toma 32 bytes:
    // Bits [8:5] = Índice de la pregunta (0 a 9)
    // Bits [4:0] = Offset del caracter (0 a 31)
    assign rom_question_num = uart_rom_addr[8:5]; 
    assign rom_question_off = uart_rom_addr[4:0]; 
    
    // El byte extraído de la ROM del LCD se entrega a la UART
    assign uart_rom_data = lcd_question_byte;

    // =========================================================================
    // Instancia 1: Sistema UART
    // =========================================================================
    uart_system #(
        .MSG_LEN(MSG_LEN)
    ) u_uart_system (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .start_tx_i  (uart_start_tx_i),
        .base_addr_i (uart_base_addr_i),
        .tx_done_o   (uart_tx_done_o),
        .rx_done_o   (uart_rx_done_o),
        .rx_data_o   (uart_rx_data_o),
        .rom_addr_o  (uart_rom_addr),   // Salida de UART...
        .rom_data_i  (uart_rom_data),   // ...conectada al puente interno
        .rx          (rx),
        .tx          (tx)
    );

    // =========================================================================
    // Instancia 2: Periférico LCD
    // =========================================================================
    lcd_peripheral u_lcd_peripheral (
        .clk_i           (clk_i),
        .rst_i           (rst_i),
        .write_enable_i  (lcd_we_i),
        .addr_i          (lcd_addr_i),
        .wdata_i         (lcd_wdata_i),
        .rdata_o         (lcd_rdata_o),
        .lcd_rs          (lcd_rs),
        .lcd_rw          (lcd_rw),
        .lcd_e           (lcd_e),
        .lcd_d           (lcd_d),
        // Puertos de ROM embebidos (solicitados por la UART internamente)
        .question_num    (rom_question_num),
        .question_off    (rom_question_off),
        .question_byte_o (lcd_question_byte),
        .option_byte_o   (lcd_option_byte_o)
    );

    // =========================================================================
    // Instancia 3: Controlador de 7 Segmentos
    // =========================================================================
    segments u_segments (
        .clk_i        (clk_i),
        .rst_i        (rst_i),
        .timer_i      (timer_i),
        .score_fpga_i (score_fpga_i),
        .score_pc_i   (score_pc_i),
        .seg_o        (seg_o),
        .an_o         (an_o),
        .dp_o         (dp_o)
    );

    // =========================================================================
    // Instancia 4: Controlador del Buzzer
    // =========================================================================
    buzzer u_buzzer (
        .clk          (clk_i),
        .rst          (rst_i),
        .play_ok      (play_ok_i),
        .play_error   (play_error_i),
        .buzzer       (buzzer_pin)
    );

endmodule