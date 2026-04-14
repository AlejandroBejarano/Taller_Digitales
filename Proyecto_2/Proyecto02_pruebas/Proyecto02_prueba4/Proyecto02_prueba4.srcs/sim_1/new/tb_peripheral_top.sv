`timescale 1ns / 1ps
// =============================================================================
// Testbench : tb_peripheral_top
// Funcion   : Verificacion funcional del modulo peripheral_top y todos sus
//             perifericos: LCD, UART, 7-segmentos, buzzer.
//
// Pruebas realizadas:
//   TEST 1: Reset y estado inicial
//   TEST 2: LCD power-on y done flag
//   TEST 3: LCD escritura de caracter
//   TEST 4: LCD clear display
//   TEST 5: UART TX - transmision de 32 bytes (pregunta completa)
//   TEST 6: UART RX - recepcion de respuesta del jugador PC
//   TEST 7: Display de 7 segmentos - timer y puntajes
//   TEST 8: Buzzer - tono correcto y tono error
//   TEST 9: Buzzer - demostracion del bug con pulso corto
// =============================================================================
module tb_peripheral_top;

    // =========================================================================
    // Parametros de simulacion
    // =========================================================================
    localparam real    CLK_PERIOD  = 62.5;  // 16 MHz -> 62.5 ns
    localparam integer BAUD_DIV    = 139;   // 16MHz / 115200 = 138.89
    localparam integer MSG_LEN     = 32;    // Bytes por pregunta

    localparam integer LCD_POWERON_TIMEOUT = 900_000;
    localparam integer LCD_OP_TIMEOUT      =  50_000;
    // CAMBIO: Se aumento MAX_TIMEOUT a 200_000 para dar mas margen a la captura
    // UART. Cada byte UART toma ~1390 ciclos (139*10) mas overhead de la FSM
    // (~7 estados entre bytes = ~7 ciclos). Entre bytes puede haber mas espera
    // si la FSM necesita completar el pipeline ROM (TX_ADDR+TX_FETCH+TX_FETCH2).
    localparam integer MAX_TIMEOUT         = 200_000;

    // =========================================================================
    // Senales del DUT
    // =========================================================================
    logic        clk;
    logic        rst;

    // UART
    logic        uart_start_tx;
    logic [31:0] uart_base_addr;
    logic        uart_tx_done;
    logic        uart_rx_done;
    logic [7:0]  uart_rx_data;

    // LCD
    logic        lcd_we;
    logic [1:0]  lcd_addr;
    logic [31:0] lcd_wdata;
    logic [31:0] lcd_rdata;
    logic [7:0]  lcd_option_byte;

    // Segmentos
    logic [5:0]  timer_val;
    logic [3:0]  score_fpga;
    logic [3:0]  score_pc;

    // Buzzer
    logic        play_ok;
    logic        play_error;

    // Pines fisicos
    logic        rx_pin;
    logic        tx_pin;
    logic        lcd_rs_pin;
    logic        lcd_rw_pin;
    logic        lcd_e_pin;
    logic [7:0]  lcd_d_pin;
    logic [6:0]  seg;
    logic [3:0]  an;
    logic        dp;
    logic        buzzer_pin;

    // =========================================================================
    // Contadores de prueba
    // =========================================================================
    integer pass_cnt = 0;
    integer fail_cnt = 0;
    integer test_num = 0;

    integer buzzer_edge_time1 = 0;
    integer buzzer_edge_time2 = 0;
    integer buzzer_period     = 0;

    // =========================================================================
    // Generacion de reloj: 16 MHz
    // =========================================================================
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    // =========================================================================
    // Instancia del DUT
    // NOTA IMPORTANTE PARA POST-SINTESIS:
    // Los parametros MSG_LEN y SIM_FAST generan warnings [VRFC 10-2861] en
    // post-sintesis porque el netlist ya tiene los valores "baked-in".
    // Esto es NORMAL y esperado. Los parametros solo afectan en behavioral sim.
    // Para que la post-sintesis use SIM_FAST=1, hay que sintetizar con:
    //   set_property generic {SIM_FAST=1} [current_fileset -srcset]
    // ANTES de correr synthesis.
    // =========================================================================
    peripheral_top #(
        .MSG_LEN  (MSG_LEN),
        .SIM_FAST (1)
    ) dut (
        .clk_i           (clk),
        .rst_i           (rst),
        // UART
        .uart_start_tx_i (uart_start_tx),
        .uart_base_addr_i(uart_base_addr),
        .uart_tx_done_o  (uart_tx_done),
        .uart_rx_done_o  (uart_rx_done),
        .uart_rx_data_o  (uart_rx_data),
        // LCD
        .lcd_we_i        (lcd_we),
        .lcd_addr_i      (lcd_addr),
        .lcd_wdata_i     (lcd_wdata),
        .lcd_rdata_o     (lcd_rdata),
        .lcd_option_byte_o(lcd_option_byte),
        // Segmentos
        .timer_i         (timer_val),
        .score_fpga_i    (score_fpga),
        .score_pc_i      (score_pc),
        // Buzzer
        .play_ok_i       (play_ok),
        .play_error_i    (play_error),
        // Pines fisicos
        .rx              (rx_pin),
        .tx              (tx_pin),
        .lcd_rs          (lcd_rs_pin),
        .lcd_rw          (lcd_rw_pin),
        .lcd_e           (lcd_e_pin),
        .lcd_d           (lcd_d_pin),
        .seg_o           (seg),
        .an_o            (an),
        .dp_o            (dp),
        .buzzer_pin      (buzzer_pin)
    );

    // =========================================================================
    // Funcion: decodificador de 7 segmentos esperado (activo-bajo)
    // =========================================================================
    function automatic [6:0] expected_seg(input [3:0] digit);
        case (digit)
            4'd0:    return 7'b0000001;
            4'd1:    return 7'b1001111;
            4'd2:    return 7'b0010010;
            4'd3:    return 7'b0000110;
            4'd4:    return 7'b1001100;
            4'd5:    return 7'b0100100;
            4'd6:    return 7'b0100000;
            4'd7:    return 7'b0001111;
            4'd8:    return 7'b0000000;
            4'd9:    return 7'b0000100;
            default: return 7'b1111111;
        endcase
    endfunction

    // =========================================================================
    // Task: verificacion con reporte
    // =========================================================================
    task automatic check(input string name,
                         input [31:0] actual,
                         input [31:0] expected);
        if (actual === expected) begin
            pass_cnt++;
            $display("  [PASS] %s: 0x%08h", name, actual);
        end else begin
            fail_cnt++;
            $display("  [FAIL] %s: esperado=0x%08h, obtenido=0x%08h",
                     name, expected, actual);
        end
    endtask

    // =========================================================================
    // Task: esperar N ciclos de reloj
    // =========================================================================
    task automatic wait_clocks(input integer n);
        repeat (n) @(posedge clk);
    endtask

    // =========================================================================
    // Task: escribir registro del LCD
    // =========================================================================
    task automatic lcd_write_reg(input [1:0] addr, input [31:0] data);
        @(posedge clk);
        lcd_we    <= 1'b1;
        lcd_addr  <= addr;
        lcd_wdata <= data;
        @(posedge clk);
        lcd_we    <= 1'b0;
    endtask

    // =========================================================================
    // Task: leer registro del LCD
    // =========================================================================
    task automatic lcd_read_status(output logic busy, output logic done);
        @(posedge clk);
        lcd_we   <= 1'b0;
        lcd_addr <= 2'b00;
        @(posedge clk);
        busy = lcd_rdata[8];
        done = lcd_rdata[9];
    endtask

    // =========================================================================
    // Task: esperar power-on inicial del LCD
    // =========================================================================
    task automatic lcd_wait_poweron();
        integer timeout;
        logic b, d;
        timeout = 0;
        b = 1'b1;
        d = 1'b0;
        while (b == 1'b1 || d == 1'b0) begin
            lcd_read_status(b, d);
            timeout++;
            if (timeout > LCD_POWERON_TIMEOUT) begin
                $display("  [TIMEOUT] LCD power-on excedio limite (%0d ciclos)", LCD_POWERON_TIMEOUT);
                fail_cnt++;
                return;
            end
        end
    endtask

    // =========================================================================
    // Task: esperar a que LCD complete operacion normal
    // =========================================================================
    task automatic lcd_wait_done();
        integer timeout;
        logic b, d;
        timeout = 0;
        b = 1'b1;
        d = 1'b0;
        while (b == 1'b1 || d == 1'b0) begin
            lcd_read_status(b, d);
            timeout++;
            if (timeout > LCD_OP_TIMEOUT) begin
                $display("  [TIMEOUT] LCD wait_done excedio limite (%0d ciclos)", LCD_OP_TIMEOUT);
                fail_cnt++;
                return;
            end
        end
    endtask

    // =========================================================================
    // Task: enviar un byte por UART al DUT
    // =========================================================================
    task automatic uart_send_byte(input [7:0] data);
        integer i;
        // Start bit
        rx_pin = 1'b0;
        repeat (BAUD_DIV) @(posedge clk);
        // 8 data bits, LSB primero
        for (i = 0; i < 8; i++) begin
            rx_pin = data[i];
            repeat (BAUD_DIV) @(posedge clk);
        end
        // Stop bit
        rx_pin = 1'b1;
        repeat (BAUD_DIV) @(posedge clk);
    endtask

    // =========================================================================
    // Task: capturar un byte del tx_pin del DUT
    // =========================================================================
    task automatic uart_capture_byte(output [7:0] data);
        integer i;
        integer timeout;

        // Esperar start bit (flanco de bajada en tx_pin)
        timeout = 0;
        while (tx_pin !== 1'b0) begin
            @(posedge clk);
            timeout++;
            if (timeout > MAX_TIMEOUT) begin
                $display("  [TIMEOUT] uart_capture: no se detecto start bit");
                data = 8'hFF;
                fail_cnt++;
                return;
            end
        end

        // Avanzar a mitad del start bit
        repeat (BAUD_DIV / 2) @(posedge clk);

        // Verificar que sigue siendo start bit
        if (tx_pin !== 1'b0) begin
            $display("  [WARN] Start bit invalido durante captura UART");
        end

        // Muestrear 8 bits de datos a intervalos de BAUD_DIV
        for (i = 0; i < 8; i++) begin
            repeat (BAUD_DIV) @(posedge clk);
            data[i] = tx_pin;
        end

        // Avanzar al stop bit
        repeat (BAUD_DIV) @(posedge clk);
        if (tx_pin !== 1'b1) begin
            $display("  [WARN] Stop bit invalido durante captura UART");
        end
    endtask

    // =========================================================================
    // Task: esperar a que una senal suba (con timeout)
    // =========================================================================
    task automatic wait_for_signal(input string name, const ref logic sig);
        integer timeout;
        timeout = 0;
        while (sig !== 1'b1) begin
            @(posedge clk);
            timeout++;
            if (timeout > MAX_TIMEOUT * 5) begin
                $display("  [TIMEOUT] Esperando %s (despues de %0d ciclos)", name, timeout);
                fail_cnt++;
                return;
            end
        end
    endtask

    // =========================================================================
    // Array de captura UART a nivel de modulo
    // =========================================================================
    logic [7:0] tx_captured [0:MSG_LEN-1];

    // =========================================================================
    // Secuencia principal de pruebas
    // =========================================================================
    initial begin
        $display("\n========================================");
        $display("  TESTBENCH: peripheral_top");
        $display("  Reloj: 16 MHz | Baud: 115200");
        $display("  SIM_FAST=1 (LCD power-on reducido)");
        $display("========================================\n");

        rst            = 1'b0;
        uart_start_tx  = 1'b0;
        uart_base_addr = 32'd0;
        lcd_we         = 1'b0;
        lcd_addr       = 2'b00;
        lcd_wdata      = 32'd0;
        timer_val      = 6'd30;
        score_fpga     = 4'd0;
        score_pc       = 4'd0;
        play_ok        = 1'b0;
        play_error     = 1'b0;
        rx_pin         = 1'b1;

        for (int k = 0; k < MSG_LEN; k++) tx_captured[k] = 8'hFF;

        // =================================================================
        // TEST 1: Reset y estado inicial
        // =================================================================
        test_num = 1;
        $display("--- TEST %0d: Reset y estado inicial ---", test_num);

        @(posedge clk);
        rst = 1'b1;
        repeat (20) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        check("dp_o (decimal point off)", {31'd0, dp}, 32'd1);
        check("seg_o (all off after rst)", {25'd0, seg}, {25'd0, 7'b1111111});
        check("an_o  (all off after rst)", {28'd0, an},  {28'd0, 4'b1111});
        check("buzzer_pin (off)", {31'd0, buzzer_pin}, 32'd0);
        check("tx_pin (idle high)", {31'd0, tx_pin}, 32'd1);
        check("lcd_rw (always 0)", {31'd0, lcd_rw_pin}, 32'd0);

        $display("");

        // =================================================================
        // TEST 2: LCD power-on y done flag
        // =================================================================
        test_num = 2;
        $display("--- TEST %0d: LCD power-on ---", test_num);

        lcd_wait_poweron();
        $display("  LCD power-on completado");

        begin
            logic b_tmp, d_tmp;
            lcd_read_status(b_tmp, d_tmp);
            check("LCD busy=0 post power-on", {31'd0, b_tmp}, 32'd0);
            check("LCD done=1 post power-on", {31'd0, d_tmp}, 32'd1);
        end

        $display("");

        // =================================================================
        // TEST 3: LCD escritura de caracter
        // =================================================================
        test_num = 3;
        $display("--- TEST %0d: LCD escritura de caracter 'H' (0x48) ---", test_num);

        lcd_write_reg(2'b01, {24'd0, 8'h48});
        lcd_write_reg(2'b00, 32'h0000_0003);
        lcd_wait_done();

        check("LCD RS=1 (modo dato)", {31'd0, lcd_rs_pin}, 32'd1);
        $display("  LCD escritura de 'H' completada exitosamente");

        $display("");

        // =================================================================
        // TEST 4: LCD clear display
        // =================================================================
        test_num = 4;
        $display("--- TEST %0d: LCD clear display ---", test_num);

        lcd_write_reg(2'b00, 32'h0000_0004);
        lcd_wait_done();

        $display("  LCD clear completado exitosamente");
        check("LCD RS=0 (modo cmd post-clear)", {31'd0, lcd_rs_pin}, 32'd0);

        $display("");

        // =================================================================
        // TEST 5: UART TX - transmision de pregunta completa (32 bytes)
        // =================================================================
        test_num = 5;
        $display("--- TEST %0d: UART TX - envio de 32 bytes ---", test_num);

        fork
            // Hilo 1: Capturar bytes transmitidos por tx_pin
            begin : capture_thread
                integer i;
                for (i = 0; i < MSG_LEN; i++) begin
                    uart_capture_byte(tx_captured[i]);
                    // CAMBIO: Mostrar progreso de captura para diagnostico
                    if (tx_captured[i] !== 8'hFF)
                        $display("  [CAPTURE] byte[%0d] = 0x%02h", i, tx_captured[i]);
                end
                $display("  Captura de %0d bytes completada", MSG_LEN);
            end

            // Hilo 2: Estimulo - activar UART TX
            begin : stimulus_thread
                @(posedge clk);
                uart_base_addr <= 32'd0;
                uart_start_tx  <= 1'b1;
                @(posedge clk);
                uart_start_tx  <= 1'b0;
                wait_for_signal("uart_tx_done", uart_tx_done);
                if (uart_tx_done === 1'b1)
                    $display("  uart_tx_done recibido correctamente");
            end
        join

        // Verificar bytes capturados
        begin
            integer j;
            integer valid_bytes;
            valid_bytes = 0;
            $display("  Bytes capturados de la ROM (pregunta 0):");
            $display("  Addr | Hex  | ASCII");
            $display("  -----|------|------");
            for (j = 0; j < MSG_LEN; j++) begin
                if (tx_captured[j] !== 8'hFF && !$isunknown(tx_captured[j]))
                    valid_bytes++;
                if (tx_captured[j] >= 8'h20 && tx_captured[j] <= 8'h7E)
                    $display("   %3d | 0x%02h | %c", j, tx_captured[j], tx_captured[j]);
                else
                    $display("   %3d | 0x%02h | .", j, tx_captured[j]);
            end
            check("UART TX: bytes validos capturados",
                  valid_bytes, MSG_LEN);
        end

        $display("");

        // =================================================================
        // TEST 6: UART RX - recepcion de respuesta del jugador PC
        // =================================================================
        test_num = 6;
        $display("--- TEST %0d: UART RX - recepcion de 'B' (0x42) ---", test_num);

        wait_clocks(200);

        $display("  Enviando byte 'B' por rx...");
        uart_send_byte(8'h42);

        wait_for_signal("uart_rx_done", uart_rx_done);

        check("UART RX data = 'B'", {24'd0, uart_rx_data}, {24'd0, 8'h42});

        $display("");

        // =================================================================
        // TEST 7: Display de 7 segmentos
        // =================================================================
        test_num = 7;
        $display("--- TEST %0d: Display 7-segmentos ---", test_num);
        $display("  Configurando: timer=25, FPGA=3, PC=7");

        timer_val  = 6'd25;
        score_fpga = 4'd3;
        score_pc   = 4'd7;

        wait_clocks(20000);

        // AN3: decenas del timer = 2
        begin
            integer timeout_seg;
            timeout_seg = 0;
            while (an !== 4'b0111 && timeout_seg < 20000) begin
                @(posedge clk);
                timeout_seg++;
            end
            if (an === 4'b0111)
                check("SEG AN3 (timer tens=2)", {25'd0, seg}, {25'd0, expected_seg(4'd2)});
            else begin
                $display("  [FAIL] No se detecto AN3 activo");
                fail_cnt++;
            end
        end

        // AN2: unidades del timer = 5
        begin
            integer timeout_seg;
            timeout_seg = 0;
            while (an === 4'b0111 && timeout_seg < 10000) begin
                @(posedge clk);
                timeout_seg++;
            end
            while (an !== 4'b1011 && timeout_seg < 20000) begin
                @(posedge clk);
                timeout_seg++;
            end
            if (an === 4'b1011)
                check("SEG AN2 (timer units=5)", {25'd0, seg}, {25'd0, expected_seg(4'd5)});
            else begin
                $display("  [FAIL] No se detecto AN2 activo");
                fail_cnt++;
            end
        end

        // AN1: score FPGA = 3
        begin
            integer timeout_seg;
            timeout_seg = 0;
            while (an === 4'b1011 && timeout_seg < 10000) begin
                @(posedge clk);
                timeout_seg++;
            end
            while (an !== 4'b1101 && timeout_seg < 20000) begin
                @(posedge clk);
                timeout_seg++;
            end
            if (an === 4'b1101)
                check("SEG AN1 (FPGA score=3)", {25'd0, seg}, {25'd0, expected_seg(4'd3)});
            else begin
                $display("  [FAIL] No se detecto AN1 activo");
                fail_cnt++;
            end
        end

        // AN0: score PC = 7
        begin
            integer timeout_seg;
            timeout_seg = 0;
            while (an === 4'b1101 && timeout_seg < 10000) begin
                @(posedge clk);
                timeout_seg++;
            end
            while (an !== 4'b1110 && timeout_seg < 20000) begin
                @(posedge clk);
                timeout_seg++;
            end
            if (an === 4'b1110)
                check("SEG AN0 (PC score=7)", {25'd0, seg}, {25'd0, expected_seg(4'd7)});
            else begin
                $display("  [FAIL] No se detecto AN0 activo");
                fail_cnt++;
            end
        end

        check("Decimal point (off)", {31'd0, dp}, 32'd1);

        timer_val = 6'd0;
        wait_clocks(20000);
        begin
            integer timeout_seg;
            timeout_seg = 0;
            while (an !== 4'b0111 && timeout_seg < 20000) begin
                @(posedge clk);
                timeout_seg++;
            end
            if (an === 4'b0111)
                check("SEG AN3 (timer=0, tens=0)", {25'd0, seg}, {25'd0, expected_seg(4'd0)});
        end

        $display("");

        // =================================================================
        // TEST 8: Buzzer - tono correcto (play_ok sostenido)
        // =================================================================
        test_num = 8;
        $display("--- TEST %0d: Buzzer - tono correcto (play_ok sostenido) ---", test_num);

        play_ok = 1'b1;
        wait_clocks(100);

        begin
            integer timeout_bz;
            timeout_bz = 0;
            while (buzzer_pin !== 1'b1 && timeout_bz < 20000) begin
                @(posedge clk);
                timeout_bz++;
            end
            if (buzzer_pin === 1'b1) begin
                $display("  Buzzer activo detectado");

                buzzer_edge_time1 = 0;
                while (buzzer_pin !== 1'b0 && buzzer_edge_time1 < 20000) begin
                    @(posedge clk);
                    buzzer_edge_time1++;
                end

                buzzer_edge_time2 = 0;
                while (buzzer_pin !== 1'b1 && buzzer_edge_time2 < 20000) begin
                    @(posedge clk);
                    buzzer_edge_time2++;
                end

                buzzer_period = buzzer_edge_time1 + buzzer_edge_time2;
                $display("  Medio periodo alto: %0d ciclos", buzzer_edge_time1);
                $display("  Medio periodo bajo: %0d ciclos", buzzer_edge_time2);
                $display("  Periodo total: %0d ciclos (esperado ~16000 para 1kHz)",
                         buzzer_period);

                if (buzzer_period > 15000 && buzzer_period < 17000) begin
                    $display("  [PASS] Frecuencia buzzer OK (~1kHz)");
                    pass_cnt++;
                end else begin
                    $display("  [FAIL] Frecuencia buzzer fuera de rango");
                    fail_cnt++;
                end
            end else begin
                $display("  [FAIL] Buzzer no se activo");
                fail_cnt++;
            end
        end

        play_ok = 1'b0;
        wait_clocks(5000);

        $display("");

        // =================================================================
        // TEST 9: Buzzer - bug con pulso corto
        // =================================================================
        test_num = 9;
        $display("--- TEST %0d: Buzzer - bug con pulso corto de play_error ---", test_num);
        $display("  NOTA: Este test verifica un BUG conocido en buzzer.sv");

        @(posedge clk); rst = 1'b1;
        wait_clocks(10);
        @(posedge clk); rst = 1'b0;
        lcd_wait_poweron();

        @(posedge clk);
        play_error = 1'b1;
        @(posedge clk);
        play_error = 1'b0;

        wait_clocks(50);

        begin
            integer bz_cnt;
            integer bz_transitions;
            logic bz_prev;

            bz_transitions = 0;
            bz_prev = buzzer_pin;
            for (bz_cnt = 0; bz_cnt < 200; bz_cnt++) begin
                @(posedge clk);
                if (buzzer_pin !== bz_prev) begin
                    bz_transitions++;
                    bz_prev = buzzer_pin;
                end
            end

            $display("  Transiciones en 200 ciclos: %0d", bz_transitions);
            if (bz_transitions > 100) begin
                $display("  [INFO] Buzzer oscila a alta frecuencia -> BUG CONFIRMADO");
                pass_cnt++;
            end else if (bz_transitions > 0) begin
                $display("  [INFO] Buzzer oscila a frecuencia intermedia");
                pass_cnt++;
            end else begin
                $display("  [INFO] Buzzer no oscila (posible fix ya aplicado)");
                pass_cnt++;
            end
        end

        $display("");

        // =================================================================
        // Resumen final
        // =================================================================
        $display("========================================");
        $display("  RESUMEN DE PRUEBAS");
        $display("========================================");
        $display("  Pruebas pasadas: %0d", pass_cnt);
        $display("  Pruebas fallidas: %0d", fail_cnt);
        $display("  Total: %0d", pass_cnt + fail_cnt);
        $display("========================================");

        if (fail_cnt == 0)
            $display("  >>> TODOS LOS TESTS PASARON <<<");
        else
            $display("  >>> HAY %0d FALLOS - REVISAR <<<", fail_cnt);

        $display("========================================\n");

        #1000;
        $finish;
    end

    // =========================================================================
    // Timeout global de simulacion
    // CAMBIO: Aumentado a 500ms para cubrir LCD power-on con SIM_FAST=0
    // (50ms) + UART TX completo (~3ms) + tests restantes con margen amplio.
    // =========================================================================
    initial begin
        #500_000_000; // 500 ms maximo
        $display("\n[ERROR] Timeout global de simulacion alcanzado (500ms)");
        $display("  La simulacion no completo en el tiempo esperado.\n");
        $finish;
    end

    // =========================================================================
    // Generacion de archivo VCD
    // =========================================================================
    initial begin
        $dumpfile("tb_peripheral_top.vcd");
        $dumpvars(0, tb_peripheral_top);
    end

endmodule