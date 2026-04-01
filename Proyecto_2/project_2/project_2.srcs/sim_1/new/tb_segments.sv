`timescale 1ns / 1ps

module segments_tb;

    // Señales del DUT
    logic        clk_i;
    logic        rst_i;
    logic [5:0]  timer_i;
    logic [3:0]  score_fpga_i;
    logic [3:0]  score_pc_i;
    wire  [6:0]  seg_o;
    wire  [3:0]  an_o;
    wire         dp_o;

    // Instancia del DUT
    segments dut (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .timer_i     (timer_i),
        .score_fpga_i(score_fpga_i),
        .score_pc_i  (score_pc_i),
        .seg_o       (seg_o),
        .an_o        (an_o),
        .dp_o        (dp_o)
    );

    // Reloj: 16 MHz → periodo = 62.5 ns
    localparam real CLK_PERIOD  = 62.5;       // ns
    localparam integer MUX_DIV  = 4000;       // igual que en el DUT
    // Ciclos para que digit_sel avance un paso
    localparam integer STEP_CYC = MUX_DIV;
    // Ciclos para un barrido completo de 4 dígitos
    localparam integer SWEEP_CYC = 4 * STEP_CYC;

    initial clk_i = 0;
    always #(CLK_PERIOD / 2) clk_i = ~clk_i;

    // Tarea: esperar N ciclos de reloj
    task wait_cycles(input integer n);
        repeat(n) @(posedge clk_i);
    endtask

    // Tarea: reset global
    task do_reset();
        rst_i = 1;
        wait_cycles(5);
        rst_i = 0;
        @(posedge clk_i);
        $display("[%0t ns] RESET liberado", $time);
    endtask

    // Tarea: verificar que dp_o siempre este apagado
    task check_dp();
        if (dp_o !== 1'b1)
            $display("  [FAIL] dp_o = %b (esperado 1)", dp_o);
        else
            $display("  [PASS] dp_o = 1 (apagado)");
    endtask

    // Tarea: verificar que durante reset los anodes y segmentos esten apagados
    task check_reset_outputs();
        if (seg_o !== 7'b1111111)
            $display("  [FAIL] seg_o durante reset = %b (esperado 1111111)", seg_o);
        else
            $display("  [PASS] seg_o durante reset = 1111111");
        if (an_o !== 4'b1111)
            $display("  [FAIL] an_o durante reset = %b (esperado 1111)", an_o);
        else
            $display("  [PASS] an_o durante reset = 1111");
    endtask

    // Tarea: esperar hasta que an_o cambie y verificar el anode esperado
    task wait_and_check_anode(
        input [3:0] expected_an,
        input [6:0] expected_seg,
        input string label
    );
        // Esperamos hasta que an_o sea el esperado (máx 2 barridos)
        automatic integer timeout = 2 * SWEEP_CYC;
        automatic integer cnt     = 0;
        while (an_o !== expected_an && cnt < timeout) begin
            @(posedge clk_i);
            cnt++;
        end
        if (cnt >= timeout) begin
            $display("  [FAIL] Timeout esperando an_o=%b para %s", expected_an, label);
        end else begin
            // Verificar segmentos en el siguiente ciclo estable
            @(posedge clk_i);
            if (seg_o !== expected_seg)
                $display("  [FAIL] %s: an_o=%b seg_o=%b (esperado %b)",
                         label, an_o, seg_o, expected_seg);
            else
                $display("  [PASS] %s: an_o=%b seg_o=%b", label, an_o, seg_o);
        end
    endtask

  
    // Tarea: verificar un valor completo en los 4 anodes para una configuracion
    task check_display(
        input [5:0] timer_val,
        input [3:0] fpga_val,
        input [3:0] pc_val,
        input string label
    );
        // Segmentos esperados segun el decodificador del DUT
        automatic logic [3:0] t_safe  = (timer_val > 30) ? 6'd30 : timer_val;
        automatic logic [3:0] t_tens  = (t_safe >= 20) ? 4'd2 :
                                        (t_safe >= 10) ? 4'd1 : 4'd0;
        automatic logic [3:0] t_units = t_safe - (t_tens == 2 ? 20 :
                                                   t_tens == 1 ? 10 : 0);

        automatic logic [6:0] seg_lut[0:10];
        seg_lut[0]  = 7'b0000001;
        seg_lut[1]  = 7'b1001111;
        seg_lut[2]  = 7'b0010010;
        seg_lut[3]  = 7'b0000110;
        seg_lut[4]  = 7'b1001100;
        seg_lut[5]  = 7'b0100100;
        seg_lut[6]  = 7'b0100000;
        seg_lut[7]  = 7'b0001111;
        seg_lut[8]  = 7'b0000000;
        seg_lut[9]  = 7'b0000100;
        seg_lut[10] = 7'b1111111; // apagado (default)

        $display("\n--- %s | timer=%0d  fpga=%0d  pc=%0d ---",
                 label, timer_val, fpga_val, pc_val);

        // Aplicar entradas
        timer_i      = timer_val;
        score_fpga_i = fpga_val;
        score_pc_i   = pc_val;

        // AN[3]: decenas del timer
        wait_and_check_anode(4'b0111, seg_lut[t_tens],  "AN[3] decenas timer");
        // AN[2]: unidades del timer
        wait_and_check_anode(4'b1011, seg_lut[t_units], "AN[2] unidades timer");
        // AN[1]: puntaje FPGA
        wait_and_check_anode(4'b1101, seg_lut[fpga_val],"AN[1] score FPGA");
        // AN[0]: puntaje PC
        wait_and_check_anode(4'b1110, seg_lut[pc_val],  "AN[0] score PC");
    endtask

    // BLOQUE PRINCIPAL
    initial begin
        // Inicializacion
        rst_i        = 0;
        timer_i      = 6'd0;
        score_fpga_i = 4'd0;
        score_pc_i   = 4'd0;

        $display("=============================================================");
        $display("  TESTBENCH: segments");
        $display("=============================================================");

        // TEST 1: Reset
        $display("\n[TEST 1] Verificacion de reset");
        rst_i = 1;
        wait_cycles(3);
        check_reset_outputs();
        check_dp();
        rst_i = 0;
        wait_cycles(2);

        // TEST 2: dp_o siempre apagado
        $display("\n[TEST 2] dp_o siempre apagado (varios ciclos)");
        repeat(SWEEP_CYC) begin
            @(posedge clk_i);
            if (dp_o !== 1'b1)
                $display("  [FAIL] dp_o=%b en t=%0t", dp_o, $time);
        end
        $display("  [PASS] dp_o = 1 durante %0d ciclos", SWEEP_CYC);

        // TEST 3: Timer = 0 s, scores = 0
        $display("\n[TEST 3] Timer=0, FPGA=0, PC=0 (caso borde inferior)");
        do_reset();
        check_display(6'd0, 4'd0, 4'd0, "T=0 F=0 P=0");

        // TEST 4: Timer = 30 s (limite superior)
        $display("\n[TEST 4] Timer=30, FPGA=7, PC=7 (caso borde superior)");
        check_display(6'd30, 4'd7, 4'd7, "T=30 F=7 P=7");

        // TEST 5: Timer fuera de rango (>30) → debe saturar en 30
        $display("\n[TEST 5] Timer=63 (fuera de rango, debe saturar a 30)");
        check_display(6'd63, 4'd3, 4'd5, "T=63->30 F=3 P=5");

        // TEST 6: Barrido de timer de 8 s a 20 s (simula conteo real)
        $display("\n[TEST 6] Barrido de timer: 8 s -> 20 s");
        score_fpga_i = 4'd2;
        score_pc_i   = 4'd1;
        for (int t = 8; t <= 20; t++) begin
            check_display(t[5:0], score_fpga_i, score_pc_i,
                          $sformatf("Timer=%0d", t));
        end

        // TEST 7: Scores FPGA incrementando de 0 a 7 y reiniciando
        $display("\n[TEST 7] Score FPGA: 0->7 y reinicio a 0");
        timer_i = 6'd15;
        score_pc_i = 4'd0;
        for (int s = 0; s <= 7; s++) begin
            check_display(6'd15, s[3:0], 4'd0,
                          $sformatf("FPGA score=%0d", s));
        end
        $display("  Reinicio FPGA score a 0...");
        check_display(6'd15, 4'd0, 4'd0, "FPGA score reiniciado=0");

        // TEST 8: Scores PC incrementando de 0 a 7 y reiniciando
        $display("\n[TEST 8] Score PC: 0->7 y reinicio a 0");
        timer_i = 6'd22;
        score_fpga_i = 4'd0;
        for (int s = 0; s <= 7; s++) begin
            check_display(6'd22, 4'd0, s[3:0],
                          $sformatf("PC score=%0d", s));
        end
        $display("  Reinicio PC score a 0...");
        check_display(6'd22, 4'd0, 4'd0, "PC score reiniciado=0");

        // TEST 9: Ambos scores cambian simultaneamente con timer fijo
        $display("\n[TEST 9] Cambio simultaneo de ambos scores, timer fijo=10");
        begin
            automatic logic [3:0] pairs[0:7][0:1] = '{
                '{4'd0, 4'd7},
                '{4'd1, 4'd6},
                '{4'd2, 4'd5},
                '{4'd3, 4'd4},
                '{4'd4, 4'd3},
                '{4'd5, 4'd2},
                '{4'd6, 4'd1},
                '{4'd7, 4'd0}
            };
            for (int i = 0; i < 8; i++) begin
                check_display(6'd10, pairs[i][0], pairs[i][1],
                              $sformatf("F=%0d P=%0d", pairs[i][0], pairs[i][1]));
            end
        end

        // TEST 10: Reset en medio de operacion normal
        $display("\n[TEST 10] Reset en medio de operacion");
        timer_i      = 6'd25;
        score_fpga_i = 4'd5;
        score_pc_i   = 4'd3;
        wait_cycles(SWEEP_CYC / 2); // a mitad de un barrido
        $display("  Aplicando reset...");
        rst_i = 1;
        wait_cycles(3);
        check_reset_outputs();
        rst_i = 0;
        wait_cycles(2);
        $display("  Verificando reanudacion tras reset con T=25 F=5 P=3");
        check_display(6'd25, 4'd5, 4'd3, "Post-reset T=25 F=5 P=3");

        // TEST 11: Cambio rapido de entradas (glitch de 1 ciclo)
        $display("\n[TEST 11] Cambio rapido de entradas entre barridos");
        timer_i      = 6'd5;
        score_fpga_i = 4'd1;
        score_pc_i   = 4'd2;
        wait_cycles(1);
        timer_i      = 6'd6;  // cambio de 1 ciclo
        wait_cycles(1);
        timer_i      = 6'd7;
        score_fpga_i = 4'd3;
        score_pc_i   = 4'd4;
        check_display(6'd7, 4'd3, 4'd4, "Post-glitch T=7 F=3 P=4");

        // TEST 12: Valores medios del timer (10, 15, 20)
        $display("\n[TEST 12] Limites de decena: 9->10->11 y 19->20->21");
        check_display(6'd9,  4'd0, 4'd0, "T=9  (decena=0)");
        check_display(6'd10, 4'd0, 4'd0, "T=10 (decena=1)");
        check_display(6'd11, 4'd0, 4'd0, "T=11 (decena=1)");
        check_display(6'd19, 4'd0, 4'd0, "T=19 (decena=1)");
        check_display(6'd20, 4'd0, 4'd0, "T=20 (decena=2)");
        check_display(6'd21, 4'd0, 4'd0, "T=21 (decena=2)");

        // FIN
        $display("\n=============================================================");
        $display("  TESTBENCH COMPLETADO");
        $display("=============================================================\n");
        $finish;
    end

    // Monitor continuo: imprime cada cambio de anode
    initial begin
        $monitor("[MON %0t ns] an_o=%b seg_o=%b dp_o=%b | timer=%0d fpga=%0d pc=%0d",
                 $time, an_o, seg_o, dp_o, timer_i, score_fpga_i, score_pc_i);
    end

    // Timeout global de seguridad
    initial begin
        #(CLK_PERIOD * 1_000_000);
        $display("[TIMEOUT] Simulacion excedio el tiempo maximo");
        $finish;
    end

endmodule