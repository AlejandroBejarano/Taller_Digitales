`timescale 1ns / 1ps
// =============================================================================
// Módulo  : uart_system
// Función : Integra uart_fsm y uart_interface en un único bloque con interfaz
//           limpia hacia el Control Principal del Juego y la ROM de preguntas.
//
//           Jerarquía:
//             uart_system
//             ├── uart_fsm       (FSM de Moore: control de TX y RX)
//             └── uart_interface (registros mapeados + core UART físico)
//
// Reloj   : 16 MHz (generado por PLL a partir de 100 MHz, spec PDF §4 punto 4)
// Baudios : 115200 (configurado dentro de uart_interface / módulo UART base)
// =============================================================================
module uart_system #(
    parameter int MSG_LEN = 32  // Propagado a uart_fsm
) (
    input  logic        clk_i,          // Reloj de 16 MHz
    input  logic        rst_i,          // Reset síncrono activo alto

    // -------------------------------------------------------------------------
    // Interfaz con el Control Principal del Juego
    // -------------------------------------------------------------------------
    input  logic        start_tx_i,     // Pulso: iniciar envío de pregunta a PC
    input  logic [31:0] base_addr_i,    // Dirección base de la pregunta en ROM
    output logic        tx_done_o,      // Pulso 1 ciclo: pregunta enviada
    output logic        rx_done_o,      // Pulso 1 ciclo: respuesta capturada
    output logic [7:0]  rx_data_o,      // Byte de respuesta (A=0x41, B=0x42...)

    // -------------------------------------------------------------------------
    // Interfaz con la ROM de preguntas (Datapath externo)
    // -------------------------------------------------------------------------
    output logic [31:0] rom_addr_o,     // Bus de direcciones a la ROM
    input  logic [7:0]  rom_data_i,     // Bus de datos de la ROM (1 byte)

    // -------------------------------------------------------------------------
    // Pines físicos UART (conectan al conector de la Basys3)
    // -------------------------------------------------------------------------
    input  logic        rx,             // FPGA_RX ← PC_TX
    output logic        tx              // FPGA_TX → PC_RX
);

    // -------------------------------------------------------------------------
    // Bus interno de 32 bits (Interfaz Estándar de Periféricos, spec §3.4.3)
    // -------------------------------------------------------------------------
    logic        internal_we;
    logic [1:0]  internal_addr;
    logic [31:0] internal_wdata;
    logic [31:0] internal_rdata;

    // -------------------------------------------------------------------------
    // Instancia: uart_fsm - FSM de Moore de control
    // -------------------------------------------------------------------------
    uart_fsm #(
        .MSG_LEN (MSG_LEN)
    ) u_fsm (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        // Control principal
        .start_tx_i  (start_tx_i),
        .base_addr_i (base_addr_i),
        .tx_done_o   (tx_done_o),
        .rx_done_o   (rx_done_o),
        .rx_data_o   (rx_data_o),
        // ROM
        .rom_addr_o  (rom_addr_o),
        .rom_data_i  (rom_data_i),
        // Bus interno
        .we_o        (internal_we),
        .addr_o      (internal_addr),
        .wdata_o     (internal_wdata),
        .rdata_i     (internal_rdata)
    );

    // -------------------------------------------------------------------------
    // Instancia: uart_interface - Registros mapeados + core UART físico
    // -------------------------------------------------------------------------
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