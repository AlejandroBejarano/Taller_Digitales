`timescale 1ns / 1ps
module tb_uart_diag;

    localparam real    CLK_PERIOD  = 62.5;
    localparam integer BAUD_DIV    = 139;
    localparam integer MSG_LEN     = 32;

    logic        clk = 1'b0;
    logic        rst;
    logic        uart_start_tx;
    logic [31:0] uart_base_addr;
    logic        uart_tx_done, uart_rx_done;
    logic [7:0]  uart_rx_data;
    logic        lcd_we = 1'b0;
    logic [1:0]  lcd_addr = 2'b00;
    logic [31:0] lcd_wdata = 32'd0;
    logic [31:0] lcd_rdata;
    logic [7:0]  lcd_option_byte;
    logic [5:0]  timer_val = 6'd0;
    logic [3:0]  score_fpga = 4'd0, score_pc = 4'd0;
    logic        play_ok = 1'b0, play_error = 1'b0;
    logic        rx_pin = 1'b1, tx_pin;
    logic        lcd_rs_pin, lcd_rw_pin, lcd_e_pin;
    logic [7:0]  lcd_d_pin;
    logic [6:0]  seg;
    logic [3:0]  an;
    logic        dp;
    logic        buzzer_pin;

    always #(CLK_PERIOD / 2.0) clk = ~clk;

    peripheral_top #(.MSG_LEN(MSG_LEN), .SIM_FAST(1)) dut (
        .clk_i(clk), .rst_i(rst),
        .uart_start_tx_i(uart_start_tx), .uart_base_addr_i(uart_base_addr),
        .uart_tx_done_o(uart_tx_done), .uart_rx_done_o(uart_rx_done),
        .uart_rx_data_o(uart_rx_data),
        .lcd_we_i(lcd_we), .lcd_addr_i(lcd_addr), .lcd_wdata_i(lcd_wdata),
        .lcd_rdata_o(lcd_rdata), .lcd_option_byte_o(lcd_option_byte),
        .timer_i(timer_val), .score_fpga_i(score_fpga), .score_pc_i(score_pc),
        .play_ok_i(play_ok), .play_error_i(play_error),
        .rx(rx_pin), .tx(tx_pin),
        .lcd_rs(lcd_rs_pin), .lcd_rw(lcd_rw_pin), .lcd_e(lcd_e_pin), .lcd_d(lcd_d_pin),
        .seg_o(seg), .an_o(an), .dp_o(dp), .buzzer_pin(buzzer_pin)
    );

    task automatic uart_capture_byte(output [7:0] data);
        integer i, timeout;
        timeout = 0;
        while (tx_pin !== 1'b0) begin
            @(posedge clk);
            timeout++;
            if (timeout > 50000) begin
                $display("[TIMEOUT] No start bit after %0d cycles", timeout);
                data = 8'hFF;
                return;
            end
        end
        repeat (BAUD_DIV / 2) @(posedge clk);
        for (i = 0; i < 8; i++) begin
            repeat (BAUD_DIV) @(posedge clk);
            data[i] = tx_pin;
        end
        repeat (BAUD_DIV) @(posedge clk);
    endtask

    initial begin
        $display("\n=== UART DIAGNOSTIC v2 ===\n");

        // =====================================================================
        // FASE 1: Monitorear send_pending DURANTE el reset
        // =====================================================================
        rst = 1'b0;
        uart_start_tx = 1'b0;
        uart_base_addr = 32'd0;

        $display("--- FASE 1: Durante y despues del reset ---");

        @(posedge clk);
        rst = 1'b1;
        $display("[%0t] rst=1 ACTIVADO", $time);

        // Monitorear cada ciclo durante reset
        repeat (5) begin
            @(posedge clk);
            $display("[%0t] RESET: sp=%b nsp=%b tx_rdy=%b tx_rdy_reg=%b rst_guard=%b tx_rdy_clean=%b new_rx=%b uart_rx_rdy=%b",
                     $time,
                     dut.u_uart.u_interface.send_pending,
                     dut.u_uart.u_interface.next_send_pending,
                     dut.u_uart.u_interface.tx_rdy,
                     dut.u_uart.u_interface.tx_rdy_reg,
                     dut.u_uart.u_interface.rst_guard,
                     dut.u_uart.u_interface.tx_rdy_clean,
                     dut.u_uart.u_interface.new_rx_flag,
                     dut.u_uart.u_interface.uart_rx_rdy);
        end

        // Desactivar reset
        @(posedge clk);
        rst = 1'b0;
        $display("[%0t] rst=0 DESACTIVADO", $time);

        // Monitorear los primeros 15 ciclos despues del reset
        repeat (15) begin
            @(posedge clk);
            $display("[%0t] POST-RST: sp=%b nsp=%b tx_rdy=%b tx_rdy_reg=%b rst_guard=%0d tx_rdy_clean=%b new_rx=%b uart_rx_rdy=%b we=%b addr=%b",
                     $time,
                     dut.u_uart.u_interface.send_pending,
                     dut.u_uart.u_interface.next_send_pending,
                     dut.u_uart.u_interface.tx_rdy,
                     dut.u_uart.u_interface.tx_rdy_reg,
                     dut.u_uart.u_interface.rst_guard,
                     dut.u_uart.u_interface.tx_rdy_clean,
                     dut.u_uart.u_interface.new_rx_flag,
                     dut.u_uart.u_interface.uart_rx_rdy,
                     dut.u_uart.u_interface.we_i,
                     dut.u_uart.u_interface.addr_i);
        end

        // =====================================================================
        // FASE 2: Esperar LCD power-on y luego probar TX
        // =====================================================================
        $display("\n--- FASE 2: Esperando LCD power-on ---");
        repeat (5000) @(posedge clk);

        $display("[%0t] Pre-TX: sp=%b tx_rdy=%b tx_rdy_clean=%b rst_guard=%0d",
                 $time,
                 dut.u_uart.u_interface.send_pending,
                 dut.u_uart.u_interface.tx_rdy,
                 dut.u_uart.u_interface.tx_rdy_clean,
                 dut.u_uart.u_interface.rst_guard);

        // Solo probar TX si send_pending es 0 (no x)
        if (dut.u_uart.u_interface.send_pending === 1'b0) begin
            $display("[OK] send_pending = 0, procediendo con TX test");

            @(posedge clk);
            uart_base_addr <= 32'd0;
            uart_start_tx  <= 1'b1;
            @(posedge clk);
            uart_start_tx  <= 1'b0;

            // Monitorear primeros ciclos de TX
            repeat (30) begin
                @(posedge clk);
                $display("[%0t] TX: state=%0d sp=%b tx_rdy=%b tx_rdy_clean=%b rom_data=0x%02h char=%0d tx_start=%b",
                         $time,
                         dut.u_uart.u_fsm.current_state,
                         dut.u_uart.u_interface.send_pending,
                         dut.u_uart.u_interface.tx_rdy,
                         dut.u_uart.u_interface.tx_rdy_clean,
                         dut.u_uart.rom_data_i,
                         dut.u_uart.u_fsm.char_counter,
                         dut.u_uart.u_interface.tx_start);
            end

            // Capturar primer byte
            begin
                logic [7:0] cap;
                uart_capture_byte(cap);
                $display("[%0t] Byte 0 captured: 0x%02h (expected 0x28)", $time, cap);
            end

            // Capturar segundo byte
            begin
                logic [7:0] cap;
                uart_capture_byte(cap);
                $display("[%0t] Byte 1 captured: 0x%02h (expected 0x20)", $time, cap);
            end
        end else begin
            $display("[FAIL] send_pending = %b (still x!), TX test skipped", 
                     dut.u_uart.u_interface.send_pending);
            $display("[DEBUG] Checking if rst_guard exists and works:");
            $display("  rst_guard = %b", dut.u_uart.u_interface.rst_guard);
            $display("  tx_rdy_reg = %b", dut.u_uart.u_interface.tx_rdy_reg);
            $display("  tx_rdy_clean = %b", dut.u_uart.u_interface.tx_rdy_clean);
            $display("  tx_rdy (raw from VHDL) = %b", dut.u_uart.u_interface.tx_rdy);
            $display("  next_send_pending = %b", dut.u_uart.u_interface.next_send_pending);
            $display("  uart_rx_rdy = %b", dut.u_uart.u_interface.uart_rx_rdy);
        end

        $display("\n=== DIAGNOSTIC v2 COMPLETE ===\n");
        #1000;
        $finish;
    end

    initial begin
        #50_000_000;
        $display("\n[TIMEOUT] Global timeout reached");
        $finish;
    end

    initial begin
        $dumpfile("tb_uart_diag.vcd");
        $dumpvars(0, tb_uart_diag);
    end

endmodule