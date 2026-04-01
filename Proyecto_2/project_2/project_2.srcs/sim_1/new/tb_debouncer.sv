`timescale 1ns / 1ps

`timescale 1ns / 1ps

module tb_debouncer_3btns();

    // 1. Declaración de Señales
    reg clk;
    reg reset;
    
    // Vectores para manejar los 3 botones
    reg  [2:0] btn_in;
    wire [2:0] btn_out;

    // Reducimos COUNT_MAX drásticamente para la simulación.
    // Si usáramos 1,000,000, la simulación tardaría demasiado en mostrar resultados.
    localparam SIM_COUNT_MAX = 20; 

    // 2. Instanciación de los Módulos (UUT - Unit Under Test)
    // Instancia para el Botón 0
    debouncer #(.COUNT_MAX(SIM_COUNT_MAX)) uut_btn0 (
        .clk(clk),
        .reset(reset),
        .btn_in(btn_in[0]),
        .btn_out(btn_out[0])
    );

    // Instancia para el Botón 1
    debouncer #(.COUNT_MAX(SIM_COUNT_MAX)) uut_btn1 (
        .clk(clk),
        .reset(reset),
        .btn_in(btn_in[1]),
        .btn_out(btn_out[1])
    );

    // Instancia para el Botón 2
    debouncer #(.COUNT_MAX(SIM_COUNT_MAX)) uut_btn2 (
        .clk(clk),
        .reset(reset),
        .btn_in(btn_in[2]),
        .btn_out(btn_out[2])
    );

    // 3. Generación del Reloj
    // Reloj de 100 MHz -> Periodo de 10 ns (5 ns en alto, 5 ns en bajo)
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // 4. Tarea para simular el "Rebote" (Bouncing) mecánico
    task apply_bounce;
        input integer btn_idx;
        input reg final_state;
        integer i;
        begin
            // Generar múltiples transiciones rápidas (ruido)
            for (i = 0; i < 6; i = i + 1) begin
                btn_in[btn_idx] = ~btn_in[btn_idx];
                #13; // Espera aleatoria corta (mucho menor al tiempo de debounce)
            end
            // Establecer el estado final después del rebote
            btn_in[btn_idx] = final_state; 
        end
    endtask

    // 5. Secuencia de Estímulos
    initial begin
        // Valores iniciales
        reset = 1;
        btn_in = 3'b000;

        // Esperar algunos ciclos de reloj y liberar el reset
        #50;
        reset = 0;
        #50;

        $display("--- Inicio de simulacion del Debouncer ---");

        // === CASO 1: Pulsación Ideal (Botón 0) ===
        // Un usuario presiona el botón de forma perfecta, sin ruido.
        $display("Caso 1: Boton 0 - Pulsacion limpia");
        btn_in[0] = 1'b1;
        #(SIM_COUNT_MAX * 10 * 2); // Esperar el doble del tiempo de debounce
        btn_in[0] = 1'b0;
        #(SIM_COUNT_MAX * 10 * 2);

        // === CASO 2: Pulsación Real con Rebotes (Botón 1) ===
        // Simula la mecánica real de un pulsador de placa (como los de una Nexys o Basys).
        $display("Caso 2: Boton 1 - Pulsacion con rebotes mecanicos");
        apply_bounce(1, 1'b1); // Presionar con rebote
        #(SIM_COUNT_MAX * 10 * 2); 
        apply_bounce(1, 1'b0); // Soltar con rebote
        #(SIM_COUNT_MAX * 10 * 2);

        // === CASO 3: Ruido Electromagnético / Glitch (Botón 2) ===
        // Un pulso espurio que es más corto que COUNT_MAX. 
        // El módulo NO debería registrar esto como un cambio de estado válido.
        $display("Caso 3: Boton 2 - Ruido/Glitch de corta duracion");
        btn_in[2] = 1'b1;
        #(SIM_COUNT_MAX * 10 / 2); // Mantener por la MITAD del tiempo necesario
        btn_in[2] = 1'b0;
        #(SIM_COUNT_MAX * 10 * 2);

        // === CASO 4: Eventos Simultáneos ===
        // Presionar botones al mismo tiempo para verificar independencia.
        $display("Caso 4: Multiples botones simultaneos");
        btn_in[0] = 1'b1;           // Limpio
        apply_bounce(1, 1'b1);      // Con rebote
        btn_in[2] = 1'b1;           // Limpio
        #(SIM_COUNT_MAX * 10 * 2);

        btn_in = 3'b000;            // Soltar todos a la vez
        #(SIM_COUNT_MAX * 10 * 2);

        $display("--- Fin de simulacion ---");
        $finish;
    end

endmodule