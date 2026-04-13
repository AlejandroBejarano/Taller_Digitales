`timescale 1ns / 1ps


module tb_buzzer();

    logic clk;
    logic rst;
    logic play_ok;
    logic play_error;
    logic buzzer_out;

    // Parámetros de Tiempo
    // Reloj de 16 MHz -> Periodo = 1/16MHz = 62.5 ns
    localparam CLK_PERIOD = 62.5; 

    // Instancia
    buzzer uut (
        .clk(clk),
        .rst(rst),
        .play_ok(play_ok),
        .play_error(play_error),
        .buzzer(buzzer_out)
    );

    // Generación de Reloj (16 MHz)
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Tarea para medir el periodo del Buzzer
    // Ayuda a verificar si la frecuencia generada es la correcta
    task automatic check_frequency(input string tone_type);
        realtime t1, t2, period;
        real freq;
        begin
            @(posedge buzzer_out);
            t1 = $realtime;
            @(posedge buzzer_out);
            t2 = $realtime;
            period = t2 - t1;
            freq = 1.0 / (period * 1e-9); // Convertir ns a segundos para Hz
            $display("[%0t] Verificación de tono %s: Periodo = %0.2f ns, Freq = %0.2f Hz", 
                     $time, tone_type, period, freq);
        end
    endtask

    // Estímulos de Prueba
    initial begin
        // Inicialización
        rst = 1;
        play_ok = 0;
        play_error = 0;
        
        $display("--- Iniciando Testbench Robusto de Buzzer ---");
        #(CLK_PERIOD * 10);
        rst = 0;
        #(CLK_PERIOD * 5);

        // ESCENARIO 1: Respuesta Correcta (Tono Agudo ~1000 Hz)
        $display("\nEscenario 1: Activando play_ok");
        play_ok = 1;
        #(CLK_PERIOD);
        play_ok = 0;
        
        // Medimos la frecuencia del primer par de pulsos
        check_frequency("CORRECTO (Esperado ~1000Hz)");
        
        // Esperamos un tiempo razonable para ver la señal en la onda
        #(CLK_PERIOD * 50000); 

        // ESCENARIO 2: Intento de interrupción
        // El código tiene un candado 'if (!is_playing)', probemos si ignora un nuevo pulso
        $display("\nEscenario 2: Intentando interrumpir mientras suena");
        play_error = 1; 
        #(CLK_PERIOD);
        play_error = 0;
        #(CLK_PERIOD * 100);
        // Aquí deberías observar en las ondas que la frecuencia no cambió a 250Hz

        // ESCENARIO 3: Reset en medio de una reproducción
        $display("\nEscenario 3: Aplicando Reset durante reproducción");
        rst = 1;
        #(CLK_PERIOD * 10);
        rst = 0;
        if (buzzer_out == 0) 
            $display("OK: El buzzer se apago correctamente con el Reset.");
        else 
            $display("ERROR: El buzzer no se apago con el Reset.");

        // ESCENARIO 4: Respuesta Incorrecta (Tono Grave ~250 Hz)
        $display("\nEscenario 4: Activando play_error");
        #(CLK_PERIOD * 10);
        play_error = 1;
        #(CLK_PERIOD);
        play_error = 0;
        
        check_frequency("ERROR (Esperado ~250Hz)");
        #(CLK_PERIOD * 100000);

        // ESCENARIO 5: Prioridad Simultánea
        // Si ambos se activan al mismo tiempo, siempre gana play_ok por el always_comb
        $display("\nEscenario 5: Activacion simultanea (Prioridad)");
        rst = 1; #100; rst = 0; #100; // Limpiar estado anterior
        play_ok = 1;
        play_error = 1;
        #(CLK_PERIOD);
        play_ok = 0;
        play_error = 0;

        check_frequency("SIMULTANEO (Debe ganar play_ok ~1000Hz)");

        $display("\n--- Fin de las pruebas de frecuencia ---");
        $display("Nota: Para verificar la duracion completa de 400ms,");
        $display("la simulacion debe correr por al menos 400ms de tiempo virtual.");
        
        $finish;
    end

endmodule