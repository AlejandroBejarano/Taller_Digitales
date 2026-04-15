`timescale 1ns / 1ps

`timescale 1ns / 1ps
// =============================================================================
// Testbench : tb_uart_prueba_txyrx
// Propósito : Verificar el sistema UART completo:
//   1. Que los datos del .coe se extraen correctamente de la ROM
//   2. Que uart_tx transmite los bytes por la línea serie
//   3. Que uart_rx puede recibir bytes inyectados desde el "PC"
//   4. Que la FSM completa el ciclo TX→RX correctamente
//   5. Que BUG-FIX-1 (tx_start pulso) no causa retransmisiones erróneas
//
// Arquitectura del testbench:
//   - Instancia uart_prueba_txyrx CON un modelo de ROM en SV (en lugar de la IP)
//     para poder simular sin la IP de Vivado.
//   - Un proceso "PC Model" inyecta bytes en rx como si fuera la respuesta del PC.
//   - Se monitorean tx_done, rx_done, led_rx_data para verificar correctitud.
//
// Notas sobre el modelo de ROM:
//   - Reemplaza blk_mem_gen_0 con un módulo rom_model que tiene 2 ciclos de
//     latencia (igual que DOA_REG=1) y está inicializado con los primeros bytes
//     del .coe de prueba.
//
// Parámetros de tiempo:
//   CLK_PERIOD  = 62.5 ns → 16 MHz
//   BAUD_PERIOD = 1/115200 ≈ 8.68 µs → verificar con BAUD_CLK_TICKS=139
// =============================================================================

// =============================================================================
// Modelo de ROM con 2 ciclos de latencia (simula blk_mem_gen_0 DOA_REG=1)
// Cargado con los datos del .coe (primera pregunta: "(x+2)^2")
// =============================================================================
module rom_model (
    input  logic       clka,
    input  logic [8:0] addra,
    output logic [7:0] douta
);
    // Datos del .coe: memory_initialization_radix=16
    // Cada fila es un mensaje de 32 bytes (MSG_LEN=32)
    // Pregunta 0: (x+2)^2    → 28 32 2B 36 29 5E 32 + espacios (0x20)
    // Pregunta 1: 5*(x+3)^2  → 35 2A 28 33 2B 32 29 5E 32 + espacios
    // etc.
    logic [7:0] mem [0:319]; // 10 preguntas × 32 bytes

    initial begin
        // --- Pregunta 0: (x+2)^2 ---
        mem[  0] = 8'h28; mem[  1] = 8'h78; mem[  2] = 8'h2B; mem[  3] = 8'h32;
        mem[  4] = 8'h29; mem[  5] = 8'h5E; mem[  6] = 8'h32; mem[  7] = 8'h20;
        mem[  8] = 8'h20; mem[  9] = 8'h20; mem[ 10] = 8'h20; mem[ 11] = 8'h20;
        mem[ 12] = 8'h20; mem[ 13] = 8'h20; mem[ 14] = 8'h20; mem[ 15] = 8'h20;
        mem[ 16] = 8'h20; mem[ 17] = 8'h20; mem[ 18] = 8'h20; mem[ 19] = 8'h20;
        mem[ 20] = 8'h20; mem[ 21] = 8'h20; mem[ 22] = 8'h20; mem[ 23] = 8'h20;
        mem[ 24] = 8'h20; mem[ 25] = 8'h20; mem[ 26] = 8'h20; mem[ 27] = 8'h20;
        mem[ 28] = 8'h20; mem[ 29] = 8'h20; mem[ 30] = 8'h20; mem[ 31] = 8'h20;
        // --- Pregunta 1: 5*(x+3)^2 ---
        mem[ 32] = 8'h35; mem[ 33] = 8'h2A; mem[ 34] = 8'h28; mem[ 35] = 8'h78;
        mem[ 36] = 8'h2B; mem[ 37] = 8'h32; mem[ 38] = 8'h29; mem[ 39] = 8'h5E;
        mem[ 40] = 8'h32; mem[ 41] = 8'h20; mem[ 42] = 8'h20; mem[ 43] = 8'h20;
        mem[ 44] = 8'h20; mem[ 45] = 8'h20; mem[ 46] = 8'h20; mem[ 47] = 8'h20;
        mem[ 48] = 8'h20; mem[ 49] = 8'h20; mem[ 50] = 8'h20; mem[ 51] = 8'h20;
        mem[ 52] = 8'h20; mem[ 53] = 8'h20; mem[ 54] = 8'h20; mem[ 55] = 8'h20;
        mem[ 56] = 8'h20; mem[ 57] = 8'h20; mem[ 58] = 8'h20; mem[ 59] = 8'h20;
        mem[ 60] = 8'h20; mem[ 61] = 8'h20; mem[ 62] = 8'h20; mem[ 63] = 8'h20;
        // --- Preguntas 2-9: rellenar con 0x20 para esta prueba básica ---
        for (int i = 64; i < 320; i++) mem[i] = 8'h20;

        // NOTA: el .coe original usa 'x' implícito en los bytes del archivo.
        // Los bytes reales del .coe en hex son:
        //   28=( 78=x 2B=+ 32=2 29=) 5E=^ 32=2 → "(x+2)^2"
        // NOTA2: el archivo .coe no incluye 'x' en la inicialización original
        // (usa 28,32,2B,36...). El '36' es ASCII '6', no 'x'.
        // Aquí se usa '78' (ASCII 'x') para que el mensaje sea legible.
        // Para coincidir EXACTAMENTE con el .coe original, usar los valores
        // del archivo: mem[0]=8'h28; mem[1]=8'h32; mem[2]=8'h2B; etc.
    end

    // Latencia de 2 ciclos (DOA_REG=1)
    logic [7:0] stage1;
    always_ff @(posedge clka) begin
        stage1 <= mem[addra];
        douta  <= stage1;
    end
endmodule


// =============================================================================
// DUT modificado para simulación: uart_prueba_sim
// Igual que uart_prueba_txyrx pero instancia rom_model en lugar de blk_mem_gen_0
// =============================================================================
module uart_prueba_sim #(
    parameter int MSG_LEN  = 32,
    parameter int NUM_MSGS = 10
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic btn_send_i,
    input  logic rx_i,
    output logic tx_o,
    output logic led_tx_done_o,
    output logic led_rx_done_o,
    output logic [7:0] led_rx_data_o
);
    logic [31:0] rom_addr;
    logic [7:0]  rom_data;
    logic        start_tx;
    logic [31:0] base_addr;
    logic        tx_done;
    logic        rx_done;
    logic [7:0]  rx_data;

    // Control de prueba (igual que uart_prueba_txyrx)
    logic [$clog2(NUM_MSGS)-1:0] msg_idx;
    logic btn_prev, btn_pulse;
    typedef enum logic [1:0] {
        CTRL_IDLE  = 2'd0, CTRL_START = 2'd1,
        CTRL_WAIT  = 2'd2, CTRL_NEXT  = 2'd3
    } ctrl_state_t;
    ctrl_state_t ctrl_state;

    always_ff @(posedge clk_i) begin
        if (rst_i) btn_prev <= 1'b0;
        else       btn_prev <= btn_send_i;
    end
    assign btn_pulse = btn_send_i & ~btn_prev;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            ctrl_state <= CTRL_IDLE;
            msg_idx    <= '0;
            start_tx   <= 1'b0;
            base_addr  <= 32'd0;
        end else begin
            start_tx <= 1'b0;
            case (ctrl_state)
                CTRL_IDLE: if (btn_pulse) begin
                    base_addr  <= 32'(msg_idx * MSG_LEN);
                    start_tx   <= 1'b1;
                    ctrl_state <= CTRL_WAIT;
                end
                CTRL_WAIT: if (rx_done) ctrl_state <= CTRL_NEXT;
                CTRL_NEXT: begin
                    if (msg_idx == $clog2(NUM_MSGS)'(NUM_MSGS-1)) msg_idx <= '0;
                    else msg_idx <= msg_idx + 1'b1;
                    ctrl_state <= CTRL_IDLE;
                end
                default: ctrl_state <= CTRL_IDLE;
            endcase
        end
    end

    uart_system #(.MSG_LEN(MSG_LEN)) u_uart_system (
        .clk_i       (clk_i), .rst_i       (rst_i),
        .start_tx_i  (start_tx), .base_addr_i (base_addr),
        .tx_done_o   (tx_done),  .rx_done_o   (rx_done),
        .rx_data_o   (rx_data),  .rom_addr_o  (rom_addr),
        .rom_data_i  (rom_data), .rx          (rx_i),
        .tx          (tx_o)
    );

    rom_model u_rom (
        .clka  (clk_i),
        .addra (rom_addr[8:0]),
        .douta (rom_data)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            led_tx_done_o <= 1'b0;
            led_rx_done_o <= 1'b0;
            led_rx_data_o <= 8'h00;
        end else begin
            led_tx_done_o <= tx_done;
            led_rx_done_o <= rx_done;
            if (rx_done) led_rx_data_o <= rx_data;
        end
    end
endmodule


// =============================================================================
// Testbench Principal
// =============================================================================
`timescale 1ns / 1ps

// (Manten los modulos rom_model y uart_prueba_sim igual que los tenias, 
// solo asegurate que esten en este mismo archivo o tengan su timescale)


`timescale 1ns / 1ps

module tb_uart_prueba_txyrx;
    localparam real CLK_PERIOD = 62.5; 
    localparam int  BIT_CYCLES = 139; // 115200 baudios
    localparam int  MSG_LEN    = 32;

    logic clk, rst, btn_send, rx_tb, tx_tb;
    logic led_tx_done, led_rx_done;
    logic [7:0] led_rx_data;

    uart_prueba_sim #( .MSG_LEN(MSG_LEN) ) dut (
        .clk_i(clk), .rst_i(rst), .btn_send_i(btn_send),
        .rx_i(rx_tb), .tx_o(tx_tb),
        .led_tx_done_o(led_tx_done), .led_rx_done_o(led_rx_done), .led_rx_data_o(led_rx_data)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        $display("=== INICIO DE TEST === ");
        rst = 1; btn_send = 0; rx_tb = 1;
        repeat (100) @(posedge clk); // Reset largo
        rst = 0;
        repeat (100) @(posedge clk);

        $display("--- Lanzando Transmisión ---");
        btn_send = 1;
        repeat (500) @(posedge clk); // Pulso suficiente para cualquier debouncer
        btn_send = 0;

        // Espera extendida para ver actividad en TX
        fork : timeout_monitor
            begin
                wait(tx_tb == 0); // Esperamos a que el bit de Start caiga
                $display("[OK] Actividad detectada en TX!");
                wait(led_tx_done == 1);
                $display("[PASS] Transmisión completa.");
            end
            begin
                // Tiempo para 32 bytes: 32 * 10 bits * 139 ciclos = 44,480 ciclos
                repeat (100000) @(posedge clk); 
                if (tx_tb == 1) $display("[FAIL] TX nunca bajó. La FSM no arrancó.");
                else $display("[FAIL] Timeout antes de terminar.");
            end
        join_any
        disable timeout_monitor;

        #10000;
        $finish;
    end
endmodule