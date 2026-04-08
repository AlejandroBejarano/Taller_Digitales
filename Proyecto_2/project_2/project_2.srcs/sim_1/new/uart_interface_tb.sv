module uart_interface_tb;
    // Señales de testbench
    logic clk;
    logic rst;
    logic we;
    logic [1:0] addr;
    logic [31:0] wdata;
    logic [31:0] rdata;
    logic rx;
    logic tx;

    // Instancia del DUT
    uart_interface dut (
        .clk_i(clk),
        .rst_i(rst),
        .we_i(we),
        .addr_i(addr),
        .wdata_i(wdata),
        .rdata_o(rdata),
        .rx(rx),
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
        rst = 1; we = 0; addr = 2'b00; wdata = 32'b0; rx = 1; wait_clk(2);
        rst = 0; wait_clk(2);

        // Escribir el byte a transmitir (ejemplo: 0x41 'A')
        we = 1; addr = 2'b10; wdata = 32'h00000041; wait_clk(1);
        
        // Iniciar transmisión
        we = 1; addr = 2'b00; wdata = 32'h00000001; wait_clk(1); // send = 1
        
        // Esperar transmisión
        wait_clk(100);

        $finish;
    end
endmodule