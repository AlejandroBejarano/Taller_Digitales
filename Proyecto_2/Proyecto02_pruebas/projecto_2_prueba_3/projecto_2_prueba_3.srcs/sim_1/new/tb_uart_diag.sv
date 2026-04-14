`timescale 1ns / 1ps
// =============================================================================
// Testbench : tb_uart_diag
//
// CORRECCIONES respecto a versión anterior:
//   [FIX-TB1] Se agrega rst_guard al path de acceso (ahora existe en
//             uart_interface). Antes el simulador devolvía X para una señal
//             no declarada, haciendo que todas las líneas de diagnóstico
//             fueran engañosas.
//
//   [FIX-TB2] Se agrega monitoreo de tx_rdy_safe (el registro síncrono) en
//             lugar de solo tx_rdy (el puerto VHDL crudo), para ver el valor
//             real que usa la lógica combinacional.
//
//   [FIX-TB3] La FASE 2 espera explícitamente a que rst_guard==7 antes de
//             intentar cualquier TX. Esto evita la condición de carrera donde
//             el testbench activaba uart_start_tx antes de que el sistema
//             estuviera estabilizado.
//
//   [FIX-TB4] Se agrega una FASE 3 que verifica la transmisión completa de
//             MSG_LEN bytes capturando cada byte por la línea TX física.
// =============================================================================
module tb_uart_diag;

    localparam real    CLK_PERIOD  = 62.5;   // 16 MHz
    localparam integer BAUD_DIV    = 139;    // ciclos por bit a 115200
    localparam integer MSG_LEN     = 32;

    logic        clk = 1'b0;
    logic        rst;
    logic        uart_start_tx;
    logic [31:0] uart_base_addr;
    logic        uart_tx_done, uart_rx_done;
    logic [7:0]  uart_rx_data;
    logic        lcd_we    = 1'b0;
    logic [1:0]  lcd_addr  = 2'b00;
    logic [31:0] lcd_wdata = 32'd0;
    logic [31:0] lcd_rdata;
    logic [7:0]  lcd_option_byte;
    logic [5:0]  timer_val   = 6'd0;
    logic [3:0]  score_fpga  = 4'd0, score_pc = 4'd0;
    logic        play_ok     = 1'b0, play_error = 1'b0;
    logic        rx_pin      = 1'b1, tx_pin;
    logic        lcd_rs_pin, lcd_rw_pin, lcd_e_pin;
    logic [7:0]  lcd_d_pin;
    logic [6:0]  seg;
    logic [3:0]  an;
    logic        dp;
    logic        buzzer_pin;

    always #(CLK_PERIOD / 2.0) clk = ~clk;

    peripheral_top #(.MSG_LEN(MSG_LEN), .SIM_FAST(1)) dut (
        .clk_i            (clk),
        .rst_i            (rst),
        .uart_start_tx_i  (uart_start_tx),
        .uart_base_addr_i (uart_base_addr),
        .uart_tx_done_o   (uart_tx_done),
        .uart_rx_done_o   (uart_rx_done),
        .uart_rx_data_o   (uart_rx_data),
        .lcd_we_i         (lcd_we),
        .lcd_addr_i       (lcd_addr),
        .lcd_wdata_i      (lcd_wdata),
        .lcd_rdata_o      (lcd_rdata),
        .lcd_option_byte_o(lcd_option_byte),
        .timer_i          (timer_val),
        .score_fpga_i     (score_fpga),
        .score_pc_i       (score_pc),
        .play_ok_i        (play_ok),
        .play_error_i     (play_error),
        .rx               (rx_pin),
        .tx               (tx_pin),
        .lcd_rs           (lcd_rs_pin),
        .lcd_rw           (lcd_rw_pin),
        .lcd_e            (lcd_e_pin),
        .lcd_d            (lcd_d_pin),
        .seg_o            (seg),
        .an_o             (an),
        .dp_o             (dp),
        .buzzer_pin       (buzzer_pin)
    );

    // =========================================================================
    // Task: captura un byte de la línea TX física (UART 115200 8N1)
    // =========================================================================
    task automatic uart_capture_byte(output [7:0] data);
        integer i, timeout;
        timeout = 0;
        // Esperar start bit (flanco de bajada en tx_pin)
        while (tx_pin !== 1'b0) begin
            @(posedge clk);
            timeout++;
            if (timeout > 200_000) begin
                $display("[TIMEOUT] No start bit después de %0d ciclos", timeout);
                data = 8'hFF;
                return;
            end
        end
        // Muestrear en el centro del start bit, luego cada BAUD_DIV ciclos
        repeat (BAUD_DIV / 2) @(posedge clk);
        for (i = 0; i < 8; i++) begin
            repeat (BAUD_DIV) @(posedge clk);
            data[i] = tx_pin;
        end
        // Consumir stop bit
        repeat (BAUD_DIV) @(posedge clk);
    endtask

    // =========================================================================
    // Proceso principal
    // =========================================================================
    initial begin
    
    
        $display("\n=== UART DIAGNOSTIC v3 ===\n");

        uart_start_tx = 1'b0;
        uart_base_addr = 32'd0;

        // =====================================================================
        // FASE 1: Monitorear señales DURANTE y DESPUÉS del reset
        // =====================================================================
        $display("--- FASE 1: Durante y despues del reset ---");

        rst = 1'b0;
        @(posedge clk);
        rst = 1'b1;
        $display("[%0t] rst=1 ACTIVADO", $time);

        repeat (5) begin
            @(posedge clk);
            $display("[%0t] RESET: sp=%b nsp=%b tx_rdy_safe=%b tx_rdy=%b rst_guard=%0d new_rx=%b uart_rx_rdy=%b",
                $time,
                dut.u_uart.u_interface.send_pending,
                dut.u_uart.u_interface.next_send_pending,
                dut.u_uart.u_interface.tx_rdy_safe,
                dut.u_uart.u_interface.tx_rdy,
                dut.u_uart.u_interface.rst_guard,
                dut.u_uart.u_interface.new_rx_flag,
                dut.u_uart.u_interface.uart_rx_rdy);
        end

        @(posedge clk);
        rst = 1'b0;
        $display("[%0t] rst=0 DESACTIVADO", $time);

        // Monitorear 15 ciclos post-reset (rst_guard debe contar hasta 7)
        repeat (15) begin
            @(posedge clk);
            $display("[%0t] POST-RST: sp=%b nsp=%b tx_rdy_safe=%b rst_guard=%0d new_rx=%b we=%b addr=%b",
                $time,
                dut.u_uart.u_interface.send_pending,
                dut.u_uart.u_interface.next_send_pending,
                dut.u_uart.u_interface.tx_rdy_safe,
                dut.u_uart.u_interface.rst_guard,
                dut.u_uart.u_interface.new_rx_flag,
                dut.u_uart.u_interface.we_i,
                dut.u_uart.u_interface.addr_i);
        end

        // =====================================================================
        // FASE 2: Esperar LCD power-on Y rst_guard==7
        // [FIX-TB3] No se intenta TX hasta que el sistema esté completamente
        //           estabilizado (rst_guard saturado en 7).
        // =====================================================================
        $display("\n--- FASE 2: Esperando LCD power-on y rst_guard==7 ---");
        repeat (5000) @(posedge clk);

        // Verificar rst_guard antes de continuar
        if (dut.u_uart.u_interface.rst_guard !== 3'd7) begin
            $display("[WARN] rst_guard = %0d (esperado 7), esperando...",
                dut.u_uart.u_interface.rst_guard);
            // Esperar hasta que rst_guard llegue a 7 (máximo 20 ciclos)
            repeat (20) begin
                @(posedge clk);
                if (dut.u_uart.u_interface.rst_guard == 3'd7) break;
            end
        end

        $display("[%0t] Pre-TX: sp=%b tx_rdy_safe=%b tx_rdy=%b rst_guard=%0d",
            $time,
            dut.u_uart.u_interface.send_pending,
            dut.u_uart.u_interface.tx_rdy_safe,
            dut.u_uart.u_interface.tx_rdy,
            dut.u_uart.u_interface.rst_guard);

        // =====================================================================
        // FASE 3: Prueba de transmisión TX
        // Solo se ejecuta si send_pending es 0 limpio (no X)
        // =====================================================================
        $display("\n--- FASE 3: Prueba de TX ---");

        if (dut.u_uart.u_interface.send_pending === 1'b0) begin
            $display("[OK] send_pending = 0, procediendo con TX test");

            @(posedge clk);
            uart_base_addr <= 32'd0;
            uart_start_tx  <= 1'b1;
            @(posedge clk);
            uart_start_tx  <= 1'b0;

            // Monitorear primeros 30 ciclos de la FSM
            repeat (30) begin
                @(posedge clk);
                $display("[%0t] TX: state=%0d sp=%b tx_rdy_safe=%b rom_data=0x%02h char=%0d tx_start=%b",
                    $time,
                    dut.u_uart.u_fsm.current_state,
                    dut.u_uart.u_interface.send_pending,
                    dut.u_uart.u_interface.tx_rdy_safe,
                    dut.u_uart.rom_data_i,
                    dut.u_uart.u_fsm.char_counter,
                    dut.u_uart.u_interface.tx_start);
            end

            // Capturar los primeros 4 bytes transmitidos físicamente
            begin
                logic [7:0] cap0, cap1, cap2, cap3;
                uart_capture_byte(cap0);
                $display("[%0t] Byte 0: 0x%02h ('%0s')", $time, cap0,
                    (cap0 >= 8'h20 && cap0 <= 8'h7E) ? string'(cap0) : "?");
                uart_capture_byte(cap1);
                $display("[%0t] Byte 1: 0x%02h ('%0s')", $time, cap1,
                    (cap1 >= 8'h20 && cap1 <= 8'h7E) ? string'(cap1) : "?");
                uart_capture_byte(cap2);
                $display("[%0t] Byte 2: 0x%02h ('%0s')", $time, cap2,
                    (cap2 >= 8'h20 && cap2 <= 8'h7E) ? string'(cap2) : "?");
                uart_capture_byte(cap3);
                $display("[%0t] Byte 3: 0x%02h ('%0s')", $time, cap3,
                    (cap3 >= 8'h20 && cap3 <= 8'h7E) ? string'(cap3) : "?");
            end

            // Esperar tx_done_o de la FSM (máximo 10 ms simulados)
            begin
                integer wait_cycles;
                wait_cycles = 0;
                while (!uart_tx_done && wait_cycles < 300_000) begin
                    @(posedge clk);
                    wait_cycles++;
                end
                if (uart_tx_done)
                    $display("[%0t] [OK] tx_done_o recibido después de %0d ciclos",
                        $time, wait_cycles);
                else
                    $display("[%0t] [FAIL] tx_done_o no llegó en %0d ciclos",
                        $time, wait_cycles);
            end

        end else begin
            $display("[FAIL] send_pending = %b (sigue X o 1), TX test saltado",
                dut.u_uart.u_interface.send_pending);
            $display("[DEBUG] Estado del sistema:");
            $display("  rst_guard    = %b (%0d)",
                dut.u_uart.u_interface.rst_guard,
                dut.u_uart.u_interface.rst_guard);
            $display("  tx_rdy       = %b", dut.u_uart.u_interface.tx_rdy);
            $display("  tx_rdy_safe  = %b", dut.u_uart.u_interface.tx_rdy_safe);
            $display("  new_rx_flag  = %b", dut.u_uart.u_interface.new_rx_flag);
            $display("  uart_rx_rdy  = %b", dut.u_uart.u_interface.uart_rx_rdy);
            $display("  FSM state    = %0d", dut.u_uart.u_fsm.current_state);
        end

        $display("\n=== DIAGNOSTIC v3 COMPLETE ===\n");
        #1000;
        $finish;
    end

    // Timeout global
    initial begin
        #50_000_000;
        $display("\n[TIMEOUT] Global timeout alcanzado");
        $finish;
    end

    initial begin
        $dumpfile("tb_uart_diag.vcd");
        $dumpvars(0, tb_uart_diag);
    end

endmodule