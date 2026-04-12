// Testbench para top_uart: envía el número 4 por UART
`timescale 1ns/1ps

module top_uart_tb;
    // Señales de testbench
    logic clk;
    logic rst;
    logic rx;
    logic new_question;
    logic [7:0] question_selected;
    logic tx;

    // Instancia del DUT
    top_uart dut (
        .clk(clk),
        .rst(rst),
        .rx(rx),
        .new_question(new_question),
        .question_selected(question_selected),
        .tx(tx)
    );

    // Generador de reloj
    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz

    // Función para esperar N ciclos de reloj
    task wait_clk(input int cycles);
        repeat (cycles) @(posedge clk);
    endtask

    initial begin
        // Inicialización
        rst = 1;
        rx = 1;
        new_question = 0;
        question_selected = 8'd0; wait_clk(2); // Esperar 2 ciclos
        rst = 0; wait_clk(2);

        // Enviar número 4
        question_selected = 8'd4;
        new_question = 1; wait_clk(1);
        new_question = 0;

        // Esperar transmisión
        wait_clk(10000);
        $finish;
    end
endmodule