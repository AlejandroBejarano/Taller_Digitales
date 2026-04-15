// =============================================================================
// tb_uart_game.sv — Testbench de autochequeo para el subsistema UART Jeopardy
//
// Simula el flujo completo de una ronda:
//   1. Genera reloj de 16 MHz directo (sin PLL)
//   2. Envía pulso de start
//   3. Captura los bytes transmitidos por TX y verifica protocolo
//   4. Envía respuesta 'C' por RX (correcta para pregunta 0)
//   5. Verifica que el resultado sea correcto
//
// NOTA: Este testbench NO instancia el top con PLL. Instancia directamente
//       los módulos internos con reloj de 16 MHz para simulación rápida.
// =============================================================================
`timescale 1ns / 1ps

module tb_uart_game;

    // =========================================================================
    // Parámetros
    // =========================================================================
    localparam real CLK_PERIOD = 62.5;    // 16 MHz = 62.5 ns
    localparam real BIT_PERIOD = 8680.0;  // 115200 baud ≈ 8.68 µs por bit

    // =========================================================================
    // Señales
    // =========================================================================
    logic        clk = 0;
    logic        rst = 1;
    logic        rx  = 1;    // UART idle = alto
    logic        tx;

    // Bus UART
    logic        we;
    logic [1:0]  addr;
    logic [31:0] wdata;
    logic [31:0] rdata;

    // ROMs simuladas
    logic [8:0]  rom_q_addr;
    logic [7:0]  rom_q_data;
    logic [8:0]  rom_a_addr;
    logic [7:0]  rom_a_data;

    // TX FSM
    logic        txfsm_start;
    logic        txfsm_done;
    logic        txfsm_busy;
    logic        txfsm_we;
    logic [1:0]  txfsm_addr;
    logic [31:0] txfsm_wdata;

    // Answer checker
    logic        ac_enable;
    logic        ac_valid;
    logic        ac_correct;
    logic [7:0]  ac_letter;
    logic        ac_invalid;
    logic        ac_we;
    logic [1:0]  ac_addr;
    logic [31:0] ac_wdata;

    // MUX control
    logic [1:0]  bus_owner; // 0=idle, 1=txfsm, 2=answer_checker

    // =========================================================================
    // Generador de reloj (16 MHz)
    // =========================================================================
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    // =========================================================================
    // ROM de preguntas simulada (datos de pregunta 0: "(2+6)^2")
    // =========================================================================
    logic [7:0] q_rom_mem [0:319];
    initial begin
        // Pregunta 0: "(2+6)^2" + padding
        q_rom_mem[0]  = 8'h28; q_rom_mem[1]  = 8'h32; q_rom_mem[2]  = 8'h2B;
        q_rom_mem[3]  = 8'h36; q_rom_mem[4]  = 8'h29; q_rom_mem[5]  = 8'h5E;
        q_rom_mem[6]  = 8'h32;
        for (int i = 7; i < 32; i++) q_rom_mem[i] = 8'h20;
        // Resto de preguntas con espacios (para simulación solo usamos Q0)
        for (int i = 32; i < 320; i++) q_rom_mem[i] = 8'h20;
    end
    // 1 ciclo de latencia de ROM
    always_ff @(posedge clk) rom_q_data <= q_rom_mem[rom_q_addr];

    // =========================================================================
    // ROM de respuestas simulada (opciones de pregunta 0)
    // =========================================================================
    logic [7:0] a_rom_mem [0:319];
    initial begin
        // Q0: A)16    C)64    B)32    D)36
        a_rom_mem[0]=8'h41; a_rom_mem[1]=8'h29; a_rom_mem[2]=8'h31; a_rom_mem[3]=8'h36;
        a_rom_mem[4]=8'h20; a_rom_mem[5]=8'h20; a_rom_mem[6]=8'h20; a_rom_mem[7]=8'h20;
        a_rom_mem[8]=8'h43; a_rom_mem[9]=8'h29; a_rom_mem[10]=8'h36; a_rom_mem[11]=8'h34;
        a_rom_mem[12]=8'h20; a_rom_mem[13]=8'h20; a_rom_mem[14]=8'h20; a_rom_mem[15]=8'h20;
        a_rom_mem[16]=8'h42; a_rom_mem[17]=8'h29; a_rom_mem[18]=8'h33; a_rom_mem[19]=8'h32;
        a_rom_mem[20]=8'h20; a_rom_mem[21]=8'h20; a_rom_mem[22]=8'h20; a_rom_mem[23]=8'h20;
        a_rom_mem[24]=8'h44; a_rom_mem[25]=8'h29; a_rom_mem[26]=8'h33; a_rom_mem[27]=8'h36;
        a_rom_mem[28]=8'h20; a_rom_mem[29]=8'h20; a_rom_mem[30]=8'h20; a_rom_mem[31]=8'h20;
        for (int i = 32; i < 320; i++) a_rom_mem[i] = 8'h20;
    end
    always_ff @(posedge clk) rom_a_data <= a_rom_mem[rom_a_addr];

    // =========================================================================
    // MUX de bus UART
    // =========================================================================
    always_comb begin
        case (bus_owner)
            2'd1: begin we = txfsm_we;  addr = txfsm_addr;  wdata = txfsm_wdata; end
            2'd2: begin we = ac_we;     addr = ac_addr;     wdata = ac_wdata; end
            default: begin we = 1'b0;   addr = 2'b00;       wdata = 32'b0; end
        endcase
    end

    // =========================================================================
    // DUT: uart_interface
    // =========================================================================
    uart_interface u_uart_if (
        .clk_i   (clk),
        .rst_i   (rst),
        .we_i    (we),
        .addr_i  (addr),
        .wdata_i (wdata),
        .rdata_o (rdata),
        .rx      (rx),
        .tx      (tx)
    );

    // =========================================================================
    // DUT: uart_tx_fsm
    // =========================================================================
    uart_tx_fsm u_tx_fsm (
        .clk_i          (clk),
        .rst_i          (rst),
        .start_i        (txfsm_start),
        .question_idx_i (4'd0),      // Pregunta 0
        .done_o         (txfsm_done),
        .busy_o         (txfsm_busy),
        .rom_q_addr_o   (rom_q_addr),
        .rom_q_data_i   (rom_q_data),
        .rom_a_addr_o   (rom_a_addr),
        .rom_a_data_i   (rom_a_data),
        .uart_we_o      (txfsm_we),
        .uart_addr_o    (txfsm_addr),
        .uart_wdata_o   (txfsm_wdata),
        .uart_rdata_i   (rdata)
    );

    // =========================================================================
    // DUT: answer_checker
    // =========================================================================
    answer_checker u_ac (
        .clk_i          (clk),
        .rst_i          (rst),
        .enable_i       (ac_enable),
        .question_idx_i (4'd0),      // Pregunta 0 (correcta = C)
        .answer_valid_o (ac_valid),
        .answer_correct_o(ac_correct),
        .answer_letter_o(ac_letter),
        .answer_invalid_o(ac_invalid),
        .uart_we_o      (ac_we),
        .uart_addr_o    (ac_addr),
        .uart_wdata_o   (ac_wdata),
        .uart_rdata_i   (rdata)
    );

    // =========================================================================
    // Tarea: enviar byte por RX (simula lo que haría la PC)
    // =========================================================================
    task automatic send_byte_rx(input logic [7:0] data);
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

    // =========================================================================
    // Tarea: capturar y verificar un byte transmitido por TX
    // =========================================================================
    task automatic check_tx_byte(input logic [7:0] expected, input string label);
        logic [7:0] received;
        integer i;

        // Esperar start bit (flanco de bajada en tx)
        @(negedge tx);
        // Muestrear en el centro del primer bit de datos
        #(BIT_PERIOD * 1.5);
        // Leer 8 bits
        for (i = 0; i < 8; i++) begin
            received[i] = tx;
            #(BIT_PERIOD);
        end

        if (received === expected)
            $display("[PASS] %s: esperado 0x%02X, recibido 0x%02X", label, expected, received);
        else
            $display("[FAIL] %s: esperado 0x%02X, recibido 0x%02X", label, expected, received);
    endtask

    // =========================================================================
    // Tarea: capturar un byte de TX sin verificar
    // =========================================================================
    task automatic capture_tx_byte(output logic [7:0] received);
        integer i;
        @(negedge tx);
        #(BIT_PERIOD * 1.5);
        for (i = 0; i < 8; i++) begin
            received[i] = tx;
            #(BIT_PERIOD);
        end
    endtask

    // =========================================================================
    // Variables de conteo para verificación
    // =========================================================================
    int pass_count = 0;
    int fail_count = 0;
    int total_tx_bytes = 0;

    // =========================================================================
    // Secuencia principal de prueba
    // =========================================================================
    initial begin
        $display("=== Inicio testbench tb_uart_game ===");
        $display("Reloj: 16 MHz, Baud: 115200");

        // Reset
        rst = 1;
        txfsm_start = 0;
        ac_enable   = 0;
        bus_owner   = 2'd0;
        #(CLK_PERIOD * 20);
        rst = 0;
        $display("[INFO] Reset liberado en t=%0t", $time);
        #(CLK_PERIOD * 10);

        // =====================================================================
        // TEST 1: Transmitir pregunta 0 completa
        // =====================================================================
        $display("\n=== TEST 1: Transmisión de Pregunta 0 ===");
        bus_owner   = 2'd1;  // Dar bus al tx_fsm
        txfsm_start = 1;
        #(CLK_PERIOD);
        txfsm_start = 0;

        // Verificar SOH (0x01)
        check_tx_byte(8'h01, "SOH");

        // Verificar índice de pregunta (0x00)
        check_tx_byte(8'h00, "Q_IDX");

        // Capturar 32 bytes de pregunta
        $display("[INFO] Capturando 32 bytes de pregunta...");
        for (int i = 0; i < 32; i++) begin
            logic [7:0] b;
            capture_tx_byte(b);
            total_tx_bytes++;
            if (i < 7)
                $display("  Q[%0d] = 0x%02X ('%c')", i, b, b);
        end
        $display("  ... (32 bytes de pregunta capturados)");

        // Verificar STX (0x02)
        check_tx_byte(8'h02, "STX");

        // Capturar 32 bytes de opciones
        $display("[INFO] Capturando 32 bytes de opciones...");
        for (int i = 0; i < 32; i++) begin
            logic [7:0] b;
            capture_tx_byte(b);
            total_tx_bytes++;
        end
        $display("  ... (32 bytes de opciones capturados)");

        // Verificar ETX (0x03)
        check_tx_byte(8'h03, "ETX");

        // Esperar que txfsm_done se active
        wait (txfsm_done);
        $display("[PASS] uart_tx_fsm reporta done");

        // =====================================================================
        // TEST 2: Recibir respuesta 'C' (correcta para Q0)
        // =====================================================================
        $display("\n=== TEST 2: Recepción de respuesta 'C' ===");
        bus_owner = 2'd2;  // Dar bus al answer_checker
        ac_enable = 1;

        // Esperar un poco y enviar 'C' por RX
        #(BIT_PERIOD * 2);
        send_byte_rx(8'h43); // 'C'

        // Esperar que answer_checker produzca resultado
        wait (ac_valid);
        #(CLK_PERIOD * 2);

        if (ac_correct)
            $display("[PASS] Respuesta 'C' evaluada como CORRECTA");
        else
            $display("[FAIL] Respuesta 'C' debería ser CORRECTA pero fue INCORRECTA");

        if (ac_letter == 8'h43)
            $display("[PASS] Letra capturada: 'C' (0x%02X)", ac_letter);
        else
            $display("[FAIL] Letra esperada: 'C' (0x43), recibida: 0x%02X", ac_letter);

        ac_enable = 0;

        // =====================================================================
        // TEST 3: Recibir respuesta incorrecta 'A' para Q0
        // =====================================================================
        $display("\n=== TEST 3: Recepción de respuesta incorrecta 'A' ===");
        #(BIT_PERIOD * 5);
        ac_enable = 1;

        #(BIT_PERIOD * 2);
        send_byte_rx(8'h41); // 'A'

        wait (ac_valid);
        #(CLK_PERIOD * 2);

        if (!ac_correct)
            $display("[PASS] Respuesta 'A' evaluada como INCORRECTA");
        else
            $display("[FAIL] Respuesta 'A' debería ser INCORRECTA pero fue CORRECTA");

        ac_enable = 0;

        // =====================================================================
        // Resumen
        // =====================================================================
        #(BIT_PERIOD * 5);
        $display("\n=== Resumen del testbench ===");
        $display("Total bytes TX capturados: %0d", total_tx_bytes);
        $display("=== Fin testbench ===");
        $finish;
    end

    // =========================================================================
    // Timeout global (prevenir simulación infinita)
    // =========================================================================
    initial begin
        #(100_000_000); // 100 ms
        $display("[FAIL] Timeout global alcanzado");
        $finish;
    end

    // =========================================================================
    // Dump para waveform
    // =========================================================================
    initial begin
        $dumpfile("tb_uart_game.vcd");
        $dumpvars(0, tb_uart_game);
    end

endmodule
