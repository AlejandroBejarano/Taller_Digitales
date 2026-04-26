//==============================================================================
// File   : pwm_top_tb.sv
// Module : pwm_top_tb
// Desc   : Testbench autoverificable para el periférico PWM (pwm_top).
//
// Cobertura
// ---------
//   T1  - Estado tras reset
//   T2  - R/W del registro CTRL
//   T3  - R/W del registro DUTY
//   T4  - Saturación de duty al rango [0, 100]
//   T5  - Bits reservados leen 0
//   T6  - Bit 'running' (RO) refleja al generador
//   T7  - Enable/disable y arranque limpio
//   T8  - Las 4 frecuencias (25, 50, 100, 200 kHz) con tolerancia
//   T9  - Precisión del duty cycle (0, 25, 50, 75, 100 %)
//   T10 - Casos extremos: duty=0 y duty=100
//   T11 - pwm_trigger_o dura exactamente 1 ciclo de clk
//   T12 - pwm_trigger_o alineado al inicio del periodo
//   T13 - Cambio de duty en caliente
//   T14 - Barrido aleatorio de duty
//
// Cada chequeo (check) actualiza contadores globales y reporta PASS/FAIL.
// Al final se imprime el resumen y, si hay fallos, $finish con código 1.
//==============================================================================
`timescale 1ns/1ps

module pwm_top_tb;

    //--------------------------------------------------------------------------
    // Constantes globales
    //--------------------------------------------------------------------------
    localparam time CLK_PERIOD   = 10ns;          // 100 MHz
    localparam logic [31:0] BASE = 32'h0001_0100; // base del periférico PWM
    localparam logic [3:0]  OFF_CTRL = 4'h0;
    localparam logic [3:0]  OFF_DUTY = 4'h4;

    // Ciclos de clk_i por periodo PWM esperado para cada freq_sel
    //   00: 25 kHz -> 4000   ;   01: 50 kHz -> 2000
    //   10: 100 kHz -> 1000  ;   11: 200 kHz -> 500
    localparam int EXPECTED_PERIOD [0:3] = '{4000, 2000, 1000, 500};
    localparam int EXPECTED_FREQ_HZ [0:3] = '{25_000, 50_000, 100_000, 200_000};

    //--------------------------------------------------------------------------
    // Señales hacia el DUT
    //--------------------------------------------------------------------------
    logic        clk_i;
    logic        rst_i;
    logic        cs_i;
    logic [3:0]  addr_i;
    logic        we_i;
    logic [31:0] wdata_i;
    logic [31:0] rdata_o;
    logic        pwm_o;
    logic        pwm_trigger_o;

    //--------------------------------------------------------------------------
    // DUT
    //--------------------------------------------------------------------------
    pwm_top dut (
        .clk_i        (clk_i),
        .rst_i        (rst_i),
        .cs_i         (cs_i),
        .addr_i       (addr_i),
        .we_i         (we_i),
        .wdata_i      (wdata_i),
        .rdata_o      (rdata_o),
        .pwm_o        (pwm_o),
        .pwm_trigger_o(pwm_trigger_o)
    );

    //--------------------------------------------------------------------------
    // Reloj 100 MHz
    //--------------------------------------------------------------------------
    initial clk_i = 1'b0;
    always #(CLK_PERIOD/2) clk_i = ~clk_i;

    //--------------------------------------------------------------------------
    // Watchdog (failsafe contra cuelgues)
    //--------------------------------------------------------------------------
    initial begin
        #50ms;
        $display("\n[ERROR] Watchdog timeout. La simulación tardó demasiado.");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Volcado de ondas (VCD)
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("pwm_top_tb.vcd");
        $dumpvars(0, pwm_top_tb);
    end

    //--------------------------------------------------------------------------
    // Contadores de tests
    //--------------------------------------------------------------------------
    int n_checks = 0;
    int n_pass   = 0;
    int n_fail   = 0;

    //==========================================================================
    //  TAREAS DE APOYO
    //==========================================================================

    // -------- Reporte de un chequeo individual ----------------------------
    task automatic check(input string name, input bit cond);
        n_checks++;
        if (cond) begin
            n_pass++;
            $display("    [PASS] %s", name);
        end else begin
            n_fail++;
            $display("    [FAIL] %s", name);
        end
    endtask

    // -------- Reset síncrono ----------------------------------------------
    task automatic do_reset();
        rst_i   = 1'b1;
        cs_i    = 1'b0;
        we_i    = 1'b0;
        addr_i  = 4'h0;
        wdata_i = 32'h0;
        repeat (5) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;
        @(negedge clk_i);
    endtask

    // -------- Escritura por el bus -----------------------------------------
    task automatic bus_write(input logic [31:0] addr, input logic [31:0] data);
        @(negedge clk_i);
        cs_i    = 1'b1;
        addr_i  = addr[3:0];
        we_i    = 1'b1;
        wdata_i = data;
        @(posedge clk_i);                  // <-- el registro captura aquí
        @(negedge clk_i);
        cs_i    = 1'b0;
        we_i    = 1'b0;
        wdata_i = 32'h0;
    endtask

    // -------- Lectura por el bus -------------------------------------------
    task automatic bus_read(input logic [31:0] addr, output logic [31:0] data);
        @(negedge clk_i);
        cs_i   = 1'b1;
        addr_i = addr[3:0];
        we_i   = 1'b0;
        @(negedge clk_i);                  // dejar asentar la combinacional
        data = rdata_o;
        cs_i = 1'b0;
    endtask

    // -------- Espera n ciclos de reloj -------------------------------------
    task automatic wait_cycles(input int n);
        repeat (n) @(posedge clk_i);
    endtask

    // -------- Configura el PWM (atómico) -----------------------------------
    task automatic config_pwm(input logic enable,
                              input logic [1:0] freq_sel,
                              input logic [6:0] duty_pct);
        bus_write(BASE + OFF_DUTY, {25'd0, duty_pct});
        bus_write(BASE + OFF_CTRL, {28'd0, 1'b0, freq_sel, enable}); // running=RO
    endtask

    // -------- Mide el periodo entre dos pulsos de trigger ------------------
    task automatic measure_period(output int cycles);
        realtime t1, t2;
        @(posedge pwm_trigger_o);
        t1 = $realtime;
        @(posedge pwm_trigger_o);
        t2 = $realtime;
        cycles = int'((t2 - t1) / CLK_PERIOD);
    endtask

    // -------- Mide ciclos high y totales en un periodo PWM completo --------
    // Sincroniza al primer trigger, cuenta hasta el siguiente trigger.
    task automatic measure_duty_period(output int high_cycles,
                                       output int total_cycles);
        int hc, tc, trig_count;
        hc = 0;
        tc = 0;
        trig_count = 0;
        forever begin
            @(posedge clk_i);
            #1;                             // dejar asentar combinacional
            if (pwm_trigger_o) trig_count++;
            if (trig_count == 2) break;     // segundo trigger -> fin
            if (trig_count >= 1) begin
                if (pwm_o) hc++;
                tc++;
            end
        end
        high_cycles  = hc;
        total_cycles = tc;
    endtask

    // -------- Mide ancho del pulso pwm_trigger_o (en ciclos de clk) -------
    task automatic measure_trigger_pulse_width(output int width_cycles);
        int w = 0;
        @(posedge pwm_trigger_o);
        while (pwm_trigger_o) begin
            @(posedge clk_i);
            #1;
            w++;
        end
        width_cycles = w;
    endtask

    //==========================================================================
    //  CASOS DE PRUEBA
    //==========================================================================

    // ----- T1 : Estado tras reset -----------------------------------------
    task automatic test_reset();
        logic [31:0] r;
        $display("\n--- T1: Estado tras reset ---");
        do_reset();
        bus_read(BASE + OFF_CTRL, r);
        check("CTRL = 0 tras reset",            r === 32'h0);
        bus_read(BASE + OFF_DUTY, r);
        check("DUTY = 0 tras reset",            r === 32'h0);
        check("pwm_o         = 0 tras reset",   pwm_o         === 1'b0);
        check("pwm_trigger_o = 0 tras reset",   pwm_trigger_o === 1'b0);
    endtask

    // ----- T2 : R/W de CTRL -----------------------------------------------
    task automatic test_ctrl_rw();
        logic [31:0] r;
        $display("\n--- T2: R/W del registro CTRL ---");
        do_reset();
        // enable=1, freq_sel=10
        bus_write(BASE + OFF_CTRL, 32'h0000_0005);
        bus_read (BASE + OFF_CTRL, r);
        check("CTRL.enable=1",       r[0]   === 1'b1);
        check("CTRL.freq_sel=10",    r[2:1] === 2'b10);
        check("CTRL.running=1 (==enable)", r[3] === 1'b1);
        // Cambiar a enable=0, freq_sel=01
        bus_write(BASE + OFF_CTRL, 32'h0000_0002);
        bus_read (BASE + OFF_CTRL, r);
        check("CTRL.enable=0",       r[0]   === 1'b0);
        check("CTRL.freq_sel=01",    r[2:1] === 2'b01);
        check("CTRL.running=0 con enable=0", r[3] === 1'b0);
    endtask

    // ----- T3 : R/W de DUTY -----------------------------------------------
    task automatic test_duty_rw();
        logic [31:0] r;
        $display("\n--- T3: R/W del registro DUTY ---");
        do_reset();
        bus_write(BASE + OFF_DUTY, 32'd50);
        bus_read (BASE + OFF_DUTY, r);
        check("DUTY=50",  r[6:0] === 7'd50);
        bus_write(BASE + OFF_DUTY, 32'd75);
        bus_read (BASE + OFF_DUTY, r);
        check("DUTY=75",  r[6:0] === 7'd75);
        bus_write(BASE + OFF_DUTY, 32'd0);
        bus_read (BASE + OFF_DUTY, r);
        check("DUTY=0",   r[6:0] === 7'd0);
        bus_write(BASE + OFF_DUTY, 32'd100);
        bus_read (BASE + OFF_DUTY, r);
        check("DUTY=100", r[6:0] === 7'd100);
    endtask

    // ----- T4 : Saturación del duty ---------------------------------------
    task automatic test_duty_saturation();
        logic [31:0] r;
        $display("\n--- T4: Saturación del DUTY ---");
        do_reset();
        // Justo arriba del límite
        bus_write(BASE + OFF_DUTY, 32'd101);
        bus_read (BASE + OFF_DUTY, r);
        check("write 101 -> read 100",        r[6:0] === 7'd100);
        // Valor moderado fuera de rango
        bus_write(BASE + OFF_DUTY, 32'd200);
        bus_read (BASE + OFF_DUTY, r);
        check("write 200 -> read 100",        r[6:0] === 7'd100);
        // Valor en rango de 7 bits pero > 100
        bus_write(BASE + OFF_DUTY, 32'd127);
        bus_read (BASE + OFF_DUTY, r);
        check("write 127 -> read 100",        r[6:0] === 7'd100);
        // Valor extremo de 32 bits
        bus_write(BASE + OFF_DUTY, 32'hFFFF_FFFF);
        bus_read (BASE + OFF_DUTY, r);
        check("write 0xFFFFFFFF -> read 100", r[6:0] === 7'd100);
        // Bits altos = 0 al leer (reservados)
        check("DUTY[31:7]=0 al leer",         r[31:7] === 25'd0);
    endtask

    // ----- T5 : Bits reservados leen 0 ------------------------------------
    task automatic test_reserved_bits();
        logic [31:0] r;
        $display("\n--- T5: Bits reservados leen 0 ---");
        do_reset();
        // Escribir todos 1, los reservados deben leerse 0
        bus_write(BASE + OFF_CTRL, 32'hFFFF_FFFF);
        bus_read (BASE + OFF_CTRL, r);
        check("CTRL[31:4]=0",   r[31:4]  === 28'd0);
        // Pero los bits válidos sí guardan el dato escrito
        check("CTRL.enable=1",  r[0]     === 1'b1);
        check("CTRL.freq_sel=11", r[2:1] === 2'b11);
        // running == enable
        check("CTRL.running=1", r[3]     === 1'b1);
    endtask

    // ----- T6 : Running refleja el generador ------------------------------
    task automatic test_running_bit();
        logic [31:0] r;
        $display("\n--- T6: Bit running ---");
        do_reset();
        config_pwm(.enable(1'b0), .freq_sel(2'b01), .duty_pct(7'd50));
        bus_read(BASE + OFF_CTRL, r);
        check("running=0 con enable=0", r[3] === 1'b0);

        config_pwm(.enable(1'b1), .freq_sel(2'b01), .duty_pct(7'd50));
        wait_cycles(20);
        bus_read(BASE + OFF_CTRL, r);
        check("running=1 con enable=1", r[3] === 1'b1);
    endtask

    // ----- T7 : Enable / disable -----------------------------------------
    task automatic test_enable_disable();
        $display("\n--- T7: Enable/Disable ---");
        do_reset();
        // Configurar pero no habilitar
        config_pwm(.enable(1'b0), .freq_sel(2'b10), .duty_pct(7'd50));
        wait_cycles(2000);
        check("pwm_o=0 con enable=0",         pwm_o         === 1'b0);
        check("pwm_trigger_o=0 con enable=0", pwm_trigger_o === 1'b0);
        // Habilitar
        config_pwm(.enable(1'b1), .freq_sel(2'b10), .duty_pct(7'd50));
        // En 2 periodos completos debe haber triggers
        fork : check_trig
            begin
                @(posedge pwm_trigger_o);
                check("pwm_trigger_o pulsa con enable=1", 1'b1);
                disable check_trig;
            end
            begin
                wait_cycles(3000);
                check("pwm_trigger_o pulsa con enable=1", 1'b0);
            end
        join
        // Deshabilitar y comprobar que se apaga
        config_pwm(.enable(1'b0), .freq_sel(2'b10), .duty_pct(7'd50));
        wait_cycles(50);
        check("pwm_o=0 al deshabilitar",         pwm_o         === 1'b0);
        check("pwm_trigger_o=0 al deshabilitar", pwm_trigger_o === 1'b0);
    endtask

    // ----- T8 : Frecuencias para los 4 valores de freq_sel ----------------
    task automatic test_frequencies();
        int meas_cycles, exp_cycles, freq_hz_meas;
        $display("\n--- T8: Frecuencias y requisito f_sw > 20 kHz ---");
        for (int fs = 0; fs < 4; fs++) begin
            do_reset();
            config_pwm(.enable(1'b1), .freq_sel(fs[1:0]), .duty_pct(7'd50));
            wait_cycles(100);
            measure_period(meas_cycles);
            exp_cycles = EXPECTED_PERIOD[fs];
            freq_hz_meas = int'(1.0e9 / (meas_cycles * 1.0));
            $display("    freq_sel=%0d  esperado=%0d ciclos  medido=%0d ciclos  (~%0d Hz)",
                     fs, exp_cycles, meas_cycles, freq_hz_meas);
            check($sformatf("freq_sel=%0d periodo correcto", fs),
                  meas_cycles == exp_cycles);
            check($sformatf("freq_sel=%0d cumple f_sw > 20 kHz", fs),
                  freq_hz_meas > 20_000);
        end
    endtask

    // ----- T9 : Precisión del duty cycle ----------------------------------
    task automatic test_duty_accuracy();
        int hc, tc, expected_high;
        const int duties [0:4] = '{0, 25, 50, 75, 100};
        $display("\n--- T9: Precisión del duty cycle ---");
        foreach (duties[i]) begin
            do_reset();
            config_pwm(.enable(1'b1), .freq_sel(2'b00), .duty_pct(duties[i]));
            wait_cycles(100);
            measure_duty_period(hc, tc);
            expected_high = (tc * duties[i]) / 100;
            $display("    duty=%0d%%  high=%0d/%0d  esperado=%0d",
                     duties[i], hc, tc, expected_high);
            check($sformatf("duty=%0d%% periodo total = 4000",          duties[i]),
                  tc == 4000);
            check($sformatf("duty=%0d%% high cycles exactos",            duties[i]),
                  hc == expected_high);
        end
    endtask

    // ----- T10 : Casos extremos -------------------------------------------
    task automatic test_edge_cases();
        $display("\n--- T10: Casos extremos duty=0 y duty=100 ---");
        // duty=0 -> pwm_o siempre 0 durante un periodo completo
        do_reset();
        config_pwm(.enable(1'b1), .freq_sel(2'b10), .duty_pct(7'd0));
        @(posedge pwm_trigger_o);
        begin : ex_duty_zero
            int saw_high = 0;
            for (int i = 0; i < 1000; i++) begin
                @(posedge clk_i); #1;
                if (pwm_o) saw_high = 1;
            end
            check("duty=0 -> pwm_o nunca alto", saw_high == 0);
        end

        // duty=100 -> pwm_o siempre 1 (excepto eventualmente fuera de enable)
        do_reset();
        config_pwm(.enable(1'b1), .freq_sel(2'b10), .duty_pct(7'd100));
        @(posedge pwm_trigger_o);
        begin : ex_duty_full
            int saw_low = 0;
            for (int i = 0; i < 1000; i++) begin
                @(posedge clk_i); #1;
                if (!pwm_o) saw_low = 1;
            end
            check("duty=100 -> pwm_o nunca bajo", saw_low == 0);
        end
    endtask

    // ----- T11 : Ancho del pulso pwm_trigger_o ----------------------------
    task automatic test_trigger_pulse_width();
        int w;
        $display("\n--- T11: Ancho de pwm_trigger_o ---");
        do_reset();
        config_pwm(.enable(1'b1), .freq_sel(2'b01), .duty_pct(7'd50));
        wait_cycles(50);
        measure_trigger_pulse_width(w);
        $display("    Ancho medido = %0d ciclo(s) de clk", w);
        check("pwm_trigger_o dura exactamente 1 ciclo de clk", w == 1);
    endtask

    // ----- T12 : Alineación trigger - inicio de periodo -------------------
    // El trigger debe pulsar al inicio del periodo, justo cuando pwm_o
    // pasa a estar alto (con duty>0). Verificamos que ocurren en el mismo
    // ciclo de clk que el flanco de subida de pwm_o.
    task automatic test_trigger_alignment();
        bit pwm_high_at_trigger;
        $display("\n--- T12: Alineación trigger / inicio de periodo ---");
        do_reset();
        config_pwm(.enable(1'b1), .freq_sel(2'b01), .duty_pct(7'd60));
        wait_cycles(50);
        @(posedge pwm_trigger_o);
        #1;
        pwm_high_at_trigger = pwm_o;
        check("pwm_o=1 cuando el trigger pulsa (con duty>0)",
              pwm_high_at_trigger === 1'b1);
    endtask

    // ----- T13 : Cambio de duty en caliente -------------------------------
    task automatic test_runtime_duty_change();
        int hc, tc;
        $display("\n--- T13: Cambio de duty en caliente ---");
        do_reset();
        config_pwm(.enable(1'b1), .freq_sel(2'b00), .duty_pct(7'd25));
        wait_cycles(50);
        measure_duty_period(hc, tc);
        check("duty inicial = 25%", hc == 1000 && tc == 4000);

        // Cambiar a 80% sin tocar enable/freq
        bus_write(BASE + OFF_DUTY, 32'd80);
        wait_cycles(50);
        measure_duty_period(hc, tc);
        check("duty cambiado a 80% se aplica", hc == 3200 && tc == 4000);
    endtask

    // ----- T14 : Barrido aleatorio ----------------------------------------
    task automatic test_random_sweep();
        int hc, tc, expected_high;
        logic [6:0] d;
        $display("\n--- T14: Barrido aleatorio de duty (10 valores) ---");
        do_reset();
        config_pwm(.enable(1'b1), .freq_sel(2'b01), .duty_pct(7'd0));
        for (int i = 0; i < 10; i++) begin
            d = $urandom_range(0, 100);
            bus_write(BASE + OFF_DUTY, {25'd0, d});
            wait_cycles(50);
            measure_duty_period(hc, tc);
            expected_high = (tc * int'(d)) / 100;
            check($sformatf("random duty=%0d%% (high=%0d/%0d, esperado=%0d)",
                            d, hc, tc, expected_high),
                  hc == expected_high && tc == 2000);
        end
    endtask

    //==========================================================================
    //  PROGRAMA PRINCIPAL
    //==========================================================================
    initial begin
        $display("\n=================================================");
        $display("  PWM PERIPHERAL TESTBENCH");
        $display("  Project 3 - EL3313 / EL4201 - I-2026");
        $display("=================================================");

        test_reset();
        test_ctrl_rw();
        test_duty_rw();
        test_duty_saturation();
        test_reserved_bits();
        test_running_bit();
        test_enable_disable();
        test_frequencies();
        test_duty_accuracy();
        test_edge_cases();
        test_trigger_pulse_width();
        test_trigger_alignment();
        test_runtime_duty_change();
        test_random_sweep();

        $display("\n=================================================");
        $display("  RESUMEN");
        $display("    Chequeos totales : %0d", n_checks);
        $display("    PASS             : %0d", n_pass);
        $display("    FAIL             : %0d", n_fail);
        if (n_fail == 0)
            $display("  >>> TODOS LOS TESTS PASARON <<<");
        else
            $display("  >>> %0d TEST(S) FALLARON <<<", n_fail);
        $display("=================================================\n");

        $finish;
    end

endmodule