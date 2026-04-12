// =============================================================================
// uart_prueba_3_tb.sv  -  Testbench funcional
//
// Simula lo siguiente:
//  1. PLL locked despues de 200ns
//  2. FSM espera WAIT_CYCLES=200 ciclos (cambiar en uart_prueba_3.sv para sim)
//  3. Verifica que tx baja a 0 (start bit del byte 0x55)
//  4. Envia byte 0xA5 por rx y verifica que la FPGA hace eco
//
// IMPORTANTE: antes de simular, cambiar en uart_prueba_3.sv:
//   localparam int WAIT_CYCLES = 200;   // en vez de 32_000_000
// =============================================================================
`timescale 1ns/1ps

module uart_prueba_3_tb;

    // Periodo de reloj 100 MHz
    localparam real CLK_PERIOD = 10.0;   // ns
    // Periodo de un bit a 115200 baud con clk de 16 MHz
    // Un bit dura 1/115200 s = 8680 ns
    localparam real BIT_PERIOD = 8680.0; // ns

    logic clk_100MHz = 0;
    logic rst_i      = 1;
    logic rx         = 1;   // linea en reposo = 1
    logic tx;
    logic [3:0] led;

    // Generador de reloj
    always #(CLK_PERIOD/2.0) clk_100MHz = ~clk_100MHz;

    // DUT
    uart_prueba_3 dut (
        .clk_100MHz (clk_100MHz),
        .rst_i      (rst_i),
        .rx         (rx),
        .tx         (tx),
        .led        (led)
    );

    // Tarea: enviar un byte por rx (LSB primero, sin paridad, 1 stop)
    task send_byte(input logic [7:0] data);
        integer i;
        // Start bit
        rx = 1'b0;
        #(BIT_PERIOD);
        // 8 bits de datos (LSB primero)
        for (i = 0; i < 8; i++) begin
            rx = data[i];
            #(BIT_PERIOD);
        end
        // Stop bit
        rx = 1'b1;
        #(BIT_PERIOD);
    endtask

    // Tarea: esperar y verificar que tx transmite el byte esperado
    task check_tx_byte(input logic [7:0] expected);
        logic [7:0] received;
        integer i;
        // Esperar start bit (flanco bajada en tx)
        @(negedge tx);
        // Muestrear en el centro del start bit
        #(BIT_PERIOD * 1.5);
        // Leer 8 bits
        for (i = 0; i < 8; i++) begin
            received[i] = tx;
            #(BIT_PERIOD);
        end
        // Verificar
        if (received === expected)
            $display("[PASS] TX: esperado 0x%02X, recibido 0x%02X", expected, received);
        else
            $display("[FAIL] TX: esperado 0x%02X, recibido 0x%02X", expected, received);
    endtask

    // Secuencia principal
    initial begin
        $display("=== Inicio testbench uart_prueba_3 ===");
        $display("IMPORTANTE: WAIT_CYCLES debe ser 200 para simulacion");

        // Reset
        rst_i = 1;
        #(CLK_PERIOD * 10);
        rst_i = 0;
        $display("[INFO] Reset liberado en t=%0t", $time);

        // Verificar que el LED[0] (locked) sube (el PLL en sim. sube rapido)
        #(CLK_PERIOD * 50);
        $display("[INFO] LED locked = %b", led[0]);

        // Esperar la transmision automatica del byte 0x55
        // (WAIT_CYCLES=200 ciclos a 16MHz => ~12.5us desde reset)
        $display("[INFO] Esperando TX automatico de 0x55...");
        fork
            check_tx_byte(8'h55);
            begin
                #(BIT_PERIOD * 15);  // Timeout
                $display("[WARN] Timeout esperando TX de 0x55");
            end
        join_any
        disable fork;

        // Pausa entre bytes
        #(BIT_PERIOD * 5);

        // Test 2: enviar 0xA5 y verificar eco
        $display("[INFO] Enviando 0xA5, esperando eco...");
        fork
            begin
                #(BIT_PERIOD * 2);   // Pequena pausa antes de enviar
                send_byte(8'hA5);
            end
            check_tx_byte(8'hA5);
        join

        // Test 3: enviar 'A' y verificar eco
        $display("[INFO] Enviando 'A' (0x41), esperando eco...");
        fork
            begin
                #(BIT_PERIOD * 2);
                send_byte(8'h41);
            end
            check_tx_byte(8'h41);
        join

        #(BIT_PERIOD * 5);
        $display("=== Fin testbench ===");
        $finish;
    end

    // Timeout global
    initial begin
        #(10_000_000);  // 10ms
        $display("[FAIL] Timeout global alcanzado");
        $finish;
    end

    // Dump para GTKWave (si se usa Xsim o iverilog)
    initial begin
        $dumpfile("uart_prueba_3_tb.vcd");
        $dumpvars(0, uart_prueba_3_tb);
    end

endmodule