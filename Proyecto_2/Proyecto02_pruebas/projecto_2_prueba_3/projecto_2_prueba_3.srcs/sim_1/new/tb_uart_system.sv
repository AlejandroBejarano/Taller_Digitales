`timescale 1ns / 1ps
// =============================================================================
// Testbench : tb_uart_system
// DUT       : uart_fsm (con modelo behavioral de uart_interface)
// =============================================================================

module tb_uart_system;

    // =========================================================================
    // Parámetros
    // =========================================================================
    localparam int MSG_LEN        = 8;      // Tamaño de mensaje (reducido para sim)
    localparam int CLK_HALF       = 31;     // Semiperiodo: 31 ns → ~16.1 MHz
    localparam int TIMEOUT_CYCLES = 5000;   // Ciclos máximos por fase de espera

    // =========================================================================
    // Señales conectadas al DUT (uart_fsm)
    // =========================================================================
    logic        clk_i;
    logic        rst_i;
    logic        start_tx_i;
    logic [31:0] base_addr_i;
    logic        tx_done_o;
    logic        rx_done_o;
    logic [7:0]  rx_data_o;
    logic [31:0] rom_addr_o;
    logic [7:0]  rom_data_i;

    // =========================================================================
    // ROM stub (behavioral, combinacional)
    // =========================================================================
    logic [7:0] rom_mem [0:255];

    initial begin : rom_init_blk
        integer i;
        for (i = 0; i < 256; i = i + 1)
            rom_mem[i] = 8'h20; // Espacio por defecto
        
        // Pregunta 0: "HOLA    "
        rom_mem[0] = 8'h48; rom_mem[1] = 8'h4F; rom_mem[2] = 8'h4C; rom_mem[3] = 8'h41;
        
        // Pregunta 1: "ADIOS   "
        rom_mem[8]  = 8'h41; rom_mem[9]  = 8'h44; rom_mem[10] = 8'h49; rom_mem[11] = 8'h4F; rom_mem[12] = 8'h53;
    end

    assign rom_data_i = rom_mem[rom_addr_o[7:0]];

    // =========================================================================
    // Modelo behavioral de uart_interface
    // =========================================================================
    logic        intf_we;
    logic [1:0]  intf_addr;
    logic [31:0] intf_wdata;
    logic [31:0] intf_rdata;

    logic        send_pending_mdl;
    logic        new_rx_flag_mdl;
    logic [7:0]  tx_reg_mdl;
    logic [7:0]  rx_reg_mdl;

    logic        force_tx_done;
    logic        force_rx_byte;
    logic [7:0]  rx_inject_val;

    always_comb begin
        case (intf_addr)
            2'b00:   intf_rdata = {30'b0, new_rx_flag_mdl, send_pending_mdl};
            2'b11:   intf_rdata = {24'b0, rx_reg_mdl};
            default: intf_rdata = 32'b0;
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            send_pending_mdl <= 1'b0;
            new_rx_flag_mdl  <= 1'b0;
            tx_reg_mdl       <= 8'h00;
            rx_reg_mdl       <= 8'h00;
        end else begin
            // TX
            if (force_tx_done)
                send_pending_mdl <= 1'b0;
            else if (intf_we && (intf_addr == 2'b00) && intf_wdata[0])
                send_pending_mdl <= 1'b1;

            if (intf_we && (intf_addr == 2'b10))
                tx_reg_mdl <= intf_wdata[7:0];

            // RX
            if (force_rx_byte) begin
                rx_reg_mdl      <= rx_inject_val;
                new_rx_flag_mdl <= 1'b1;
            end else if (intf_we && (intf_addr == 2'b00) && !intf_wdata[1]) begin
                new_rx_flag_mdl <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Instancia del DUT: uart_fsm
    // =========================================================================
    uart_fsm #(
        .MSG_LEN (MSG_LEN)
    ) dut (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .start_tx_i  (start_tx_i),
        .base_addr_i (base_addr_i),
        .tx_done_o   (tx_done_o),
        .rx_done_o   (rx_done_o),
        .rx_data_o   (rx_data_o),
        .rom_addr_o  (rom_addr_o),
        .rom_data_i  (rom_data_i),
        .we_o        (intf_we),
        .addr_o      (intf_addr),
        .wdata_o     (intf_wdata),
        .rdata_i     (intf_rdata)
    );

    // =========================================================================
    // Reloj
    // =========================================================================
    initial clk_i = 1'b0;
    always #(CLK_HALF) clk_i = ~clk_i;

    // =========================================================================
    // Tasks auxiliares
    // =========================================================================
    task automatic apply_reset(input int cycles = 5);
        rst_i         = 1'b1;
        force_tx_done = 1'b0;
        force_rx_byte = 1'b0;
        rx_inject_val = 8'h00;
        repeat (cycles) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;
    endtask

    task automatic complete_tx(input int delay_cycles = 4);
        repeat (delay_cycles) @(posedge clk_i);
        @(negedge clk_i);
        force_tx_done = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        force_tx_done = 1'b0;
    endtask

    task automatic inject_rx_byte(input logic [7:0] byte_val, input int delay_cycles = 3);
        repeat (delay_cycles) @(posedge clk_i);
        @(negedge clk_i);
        rx_inject_val = byte_val;
        force_rx_byte = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        force_rx_byte = 1'b0;
    endtask

    task automatic check_bit(input string name, input logic got, input logic expected, ref int fc);
        if (got !== expected) begin
            $display("  [FAIL] %s: got=%b, expected=%b", name, got, expected);
            fc++;
        end else begin
            $display("  [PASS] %s", name);
        end
    endtask

    task automatic check_byte(input string name, input logic [7:0] got, input logic [7:0] expected, ref int fc);
        if (got !== expected) begin
            $display("  [FAIL] %s: got=0x%02X, expected=0x%02X", name, got, expected);
            fc++;
        end else begin
            $display("  [PASS] %s = 0x%02X", name, got);
        end
    endtask

    task automatic run_tx_phase(ref int fc, output int bytes_done);
        automatic int cy = 0;
        bytes_done = 0;
        while (!tx_done_o && cy < TIMEOUT_CYCLES) begin
            @(posedge clk_i);
            cy++;
            if (intf_we && (intf_addr == 2'b00) && intf_wdata[0]) begin
                $display("  Byte %0d: ROM[0x%02X]=0x%02X ('%c')",
                         bytes_done, rom_addr_o[7:0], rom_data_i,
                         (rom_data_i >= 8'h20 && rom_data_i < 8'h7F) ? rom_data_i : 8'h3F);
                fork complete_tx(4); join_none
                bytes_done++;
            end
        end
        if (cy >= TIMEOUT_CYCLES) begin
            $display("  [FAIL] TX phase no completó (timeout %0d ciclos)", cy);
            fc++;
        end
    endtask

    task automatic wait_rx_done(ref int fc, output logic got);
        automatic int cy = 0;
        got = 1'b0;
        while (!rx_done_o && cy < TIMEOUT_CYCLES) begin
            @(posedge clk_i);
            cy++;
        end
        if (cy >= TIMEOUT_CYCLES) begin
            $display("  [FAIL] rx_done_o nunca llegó (timeout %0d ciclos)", cy);
            fc++;
        end else begin
            got = 1'b1;
        end
    endtask

    // =========================================================================
    // Bloque principal de pruebas
    // =========================================================================
    initial begin : main_test_blk
        automatic int  fail_count  = 0;
        automatic int  test_num    = 0;
        automatic int  bytes_done  = 0;
        automatic logic rx_arrived = 1'b0;

        rst_i         = 1'b1;
        start_tx_i    = 1'b0;
        base_addr_i   = 32'd0;
        force_tx_done = 1'b0;
        force_rx_byte = 1'b0;
        rx_inject_val = 8'h00;

        $display("=============================================================");
        $display("  TB: uart_fsm | MSG_LEN=%0d | CLK_HALF=%0d ns", MSG_LEN, CLK_HALF);
        $display("=============================================================");

        // --- TEST 1 ---
        test_num++;
        $display("\n[TEST %0d] Reset y estado inicial", test_num);
        apply_reset(10);
        @(posedge clk_i);
        check_bit("tx_done_o=0 tras reset",   tx_done_o,        1'b0, fail_count);
        check_bit("rx_done_o=0 tras reset",   rx_done_o,        1'b0, fail_count);
        check_bit("intf_we=0 en IDLE",        intf_we,          1'b0, fail_count);

        // --- TEST 2 ---
        test_num++;
        $display("\n[TEST %0d] Transmisión completa de %0d bytes", test_num, MSG_LEN);
        apply_reset(5);
        base_addr_i = 32'd0;
        @(posedge clk_i);
        start_tx_i = 1'b1;
        @(posedge clk_i);
        start_tx_i = 1'b0;

        run_tx_phase(fail_count, bytes_done);
        check_bit("tx_done_o=1 al fin de TX", tx_done_o, 1'b1, fail_count);

        // --- TEST 3 ---
        test_num++;
        $display("\n[TEST %0d] Recepción de respuesta 'B' del jugador PC", test_num);
        fork inject_rx_byte(8'h42, 8); join_none
        wait_rx_done(fail_count, rx_arrived);
        if (rx_arrived) begin
            check_bit("rx_done_o=1",    rx_done_o, 1'b1, fail_count);
            check_byte("rx_data_o='B'", rx_data_o, 8'h42, fail_count);
        end
        @(posedge clk_i); // Verificar pulso
        check_bit("rx_done_o=0 ciclo siguiente (pulso)", rx_done_o, 1'b0, fail_count);

        // --- TEST 4 (CORREGIDO) ---
        test_num++;
        $display("\n[TEST %0d] start_tx_i ignorado durante TX activo", test_num);
        apply_reset(5);
        base_addr_i = 32'd0;

        @(posedge clk_i);
        start_tx_i = 1'b1;
        @(posedge clk_i);
        start_tx_i = 1'b0;

        // Disparamos un hilo paralelo para generar el "start" erróneo mientras
        // la máquina está ocupada, SIN dormir el hilo principal.
        fork
            begin
                repeat(15) @(posedge clk_i); // Garantizamos que ya está ocupada transmitiendo
                start_tx_i = 1'b1;
                @(posedge clk_i);
                start_tx_i = 1'b0;
            end
        join_none

        // Procesamos la transmisión de los bytes para que la FSM no se bloquee
        run_tx_phase(fail_count, bytes_done);
        
        if (bytes_done == MSG_LEN) 
            $display("  [PASS] start ignorado, transmisión completada (%0d bytes)", bytes_done);
        else begin
            $display("  [FAIL] La FSM se corrompió con el start espurio");
            fail_count++;
        end

        // Finalizamos RX para devolverla a IDLE sanamente
        fork inject_rx_byte(8'h41, 5); join_none
        wait_rx_done(fail_count, rx_arrived);

        // --- TEST 5 ---
        test_num++;
        $display("\n[TEST %0d] Dos rondas completas consecutivas", test_num);
        @(posedge clk_i);
        check_bit("intf_we=0 en IDLE (entre rondas)", intf_we, 1'b0, fail_count);
        
        base_addr_i = 32'd8; // Siguiente pregunta
        @(posedge clk_i);
        start_tx_i = 1'b1;
        @(posedge clk_i);
        start_tx_i = 1'b0;

        run_tx_phase(fail_count, bytes_done);
        check_bit("tx_done_o ronda 2", tx_done_o, 1'b1, fail_count);

        fork inject_rx_byte(8'h43, 5); join_none
        wait_rx_done(fail_count, rx_arrived);
        if (rx_arrived) begin
            check_bit("rx_done_o ronda 2", rx_done_o, 1'b1, fail_count);
            check_byte("rx_data_o='C' ronda 2", rx_data_o, 8'h43, fail_count);
        end

        // --- TEST 6 ---
        test_num++;
        $display("\n[TEST %0d] RX_WAIT espera sin corrupción de flags", test_num);
        apply_reset(5);
        base_addr_i = 32'd0;

        @(posedge clk_i);
        start_tx_i = 1'b1;
        @(posedge clk_i);
        start_tx_i = 1'b0;

        run_tx_phase(fail_count, bytes_done);

        repeat (30) @(posedge clk_i); // Retraso largo sin respuesta
        check_bit("rx_done_o=0 tras espera vacía", rx_done_o, 1'b0, fail_count);
        check_bit("tx_done_o=0 en RX_WAIT", tx_done_o, 1'b0, fail_count);

        fork inject_rx_byte(8'h44, 3); join_none
        wait_rx_done(fail_count, rx_arrived);
        if (rx_arrived) begin
            check_byte("rx_data_o='D' tras espera", rx_data_o, 8'h44, fail_count);
            check_bit("rx_done_o=1 tras espera", rx_done_o, 1'b1, fail_count);
        end

        // --- RESULTADOS ---
        repeat (5) @(posedge clk_i);
        $display("\n=============================================================");
        $display("  RESULTADO FINAL: %0d fallo(s) en %0d tests", fail_count, test_num);
        if (fail_count == 0)
            $display("  *** TODOS LOS TESTS PASARON EXITOSAMENTE ***");
        else
            $display("  *** REVISAR FALLOS ***");
        $display("=============================================================");
        $finish;
    end

    // Watchdog
    initial begin
        #(CLK_HALF * 2 * 500_000);
        $display("[WATCHDOG] Tiempo máximo excedido.");
        $finish;
    end

endmodule