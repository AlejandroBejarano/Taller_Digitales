`timescale 1ns / 1ps

module uart_system_tb();

    logic clk;
    logic rst;
    logic btn_send;
    logic rx;
    logic tx;

    // Reloj de 100MHz (Periodo de 10ns)
    always #5 clk = ~clk;

    // Instancia del Hardware Tester (que ya contiene tu interfaz y el VHDL)
    uart_hw_tester uut (
        .clk_i      (clk),
        .rst_i      (rst),
        .btn_send_i (btn_send),
        .rx         (rx),
        .tx         (tx)
    );

    // Tarea para simular que la PC envía un byte a la FPGA
    // A 115200 baudios, cada bit dura aprox 8680 ns
    task automatic pc_sends_byte(input [7:0] data);
        integer i;
        realtime bit_time = 8680ns; 
        
        $display("[TB] PC enviando byte 0x%h...", data);
        rx = 0; #(bit_time); // Start bit
        for (i = 0; i < 8; i = i + 1) begin
            rx = data[i]; #(bit_time); // Data bits
        end
        rx = 1; #(bit_time); // Stop bit
        $display("[TB] Byte enviado por PC.");
    endtask

    initial begin
        // Inicialización
        clk = 0; rst = 1; btn_send = 0; rx = 1;
        #100;
        rst = 0;
        #100;

        // --- PRUEBA 1: Transmisión (FPGA -> PC) ---
        $display("[TB] Simulando presionar botón para enviar 'A'...");
        btn_send = 1;
        #50; 
        btn_send = 0;
        
        // Esperamos a ver la trama en la señal 'tx'
        // Deberías ver un start bit (0), luego 01000001 (A) y stop bit (1)
        #100us; 

        // --- PRUEBA 2: Recepción (PC -> FPGA) ---
        // Simulamos que el script de Python responde con una 'B' (0x42)
        pc_sends_byte(8'h42);
        
        #20us;
        $display("[TB] Simulación terminada. Verifica los registros en la Waveform.");
        $finish;
    end
endmodule