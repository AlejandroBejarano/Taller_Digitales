`timescale 1ns / 1ps

module tb_uart_fsm;

    // --- Señales del Reloj y Sistema ---
    localparam CLK_PERIOD = 62.5; // 16 MHz
    logic clk_i, rst_i;
    
    // --- Interfaz con Control Principal ---
    logic        start_tx_i;
    logic [31:0] base_addr_i;
    logic        tx_done_o;
    logic        rx_done_o;
    logic [7:0]  rx_data_o;
    
    // --- Interfaz con ROM (Simulada) ---
    logic [31:0] rom_addr_o;
    logic [7:0]  rom_data_i;
    
    // --- Interfaz con uart_interface ---
    logic        we_o;
    logic [1:0]  addr_o;
    logic [31:0] wdata_o;
    logic [31:0] rdata_i;

    // --- Instancia del DUT (Nombre corregido y puertos alineados) ---
    uart_fsm dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .start_tx_i(start_tx_i),
        .base_addr_i(base_addr_i),
        .tx_done_o(tx_done_o),
        .rx_done_o(rx_done_o),
        .rx_data_o(rx_data_o),
        .rom_addr_o(rom_addr_o),
        .rom_data_i(rom_data_i),
        .we_o(we_o),
        .addr_o(addr_o),
        .wdata_o(wdata_o),
        .rdata_i(rdata_i)
    );

    // Generador de reloj
    initial begin
        clk_i = 0;
        forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end

    // Proceso de prueba
    initial begin
        // Inicializacion
        rst_i = 1;
        start_tx_i = 0;
        base_addr_i = 32'h0000_1000;
        rom_data_i = 8'h41; // 'A'
        rdata_i = 32'b0;    // UART idle
        #(CLK_PERIOD*5);
        rst_i = 0;
        #(CLK_PERIOD*5);

        // Iniciar transmision
        start_tx_i = 1;
        #(CLK_PERIOD);
        start_tx_i = 0;

        // Simular que la UART responde que ya envio el dato
        // Esperamos a ver we_o en alto (la FSM cargando dato)
        wait(we_o);
        #(CLK_PERIOD*2);
        
        // Simulamos que el bit 0 de rdata_i (send_pending) baja a 0
        rdata_i = 32'h0000_0000; 

        $display("Simulacion en curso: Revisar formas de onda");
        #(CLK_PERIOD*100);
        $finish;
    end

endmodule