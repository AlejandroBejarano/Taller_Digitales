`timescale 1ns / 1ps

module buzzer(
    input  logic clk,        // Reloj del sistema de 16 MHz 
    input  logic rst,
    input  logic play_ok,    // Respuesta correcta 
    input  logic play_error, // Respuesta incorrecta
    output logic buzzer      // Salida al pin del Buzzer
);

    // --- Cálculos de Frecuencia para 16 MHz ---
    // Fórmula: N = (F_clk / (2 * F_deseada))
    //N es el límite del contador para hacer toggle a la señal
    localparam int N_CORRECT = 8000;   // ~1000 Hz (Tono Agudo)
    localparam int N_ERROR   = 32000;  // ~250 Hz  (Tono Grave)
    
    // Duración del sonido (ej. 400ms para no bloquear el juego)
    // 0.4s * 16,000,000 Hz = 6,400,000 ciclos
    localparam int DURATION_LIMIT = 6400000;

    // --- Registros internos ---
    logic [31:0] counter;
    logic [31:0] n_val;
    logic [31:0] duration_counter;
    logic        is_playing;

    // --- Lógica de Selección de Tono 
    always_comb begin
        if (play_ok)
            n_val = N_CORRECT;
        else if (play_error)
            n_val = N_ERROR;
        else
            n_val = 0;
    end

    // --- Generador de Tono y Duración (Síncrono) ---
    always_ff @(posedge clk) begin
        if (rst) begin
            counter          <= 0;
            duration_counter <= 0;
            buzzer           <= 0;
            is_playing       <= 0;
        end else begin
            // Disparo del sonido
            if ((play_ok || play_error) && !is_playing) begin
                is_playing       <= 1;
                duration_counter <= 0;
                counter          <= 0;
            end
            
            // Lógica mientras suena
            if (is_playing) begin
                if (duration_counter >= DURATION_LIMIT) begin
                    is_playing <= 0;
                    buzzer     <= 0;
                end else begin
                    duration_counter <= duration_counter + 1;
                    
                    // Divisor de frecuencia (Generación del tono)
                    if (counter >= n_val) begin
                        counter <= 0;
                        buzzer  <= ~buzzer;
                    end else begin
                        counter <= counter + 1;
                    end
                end
            end else begin
                buzzer  <= 0;
                counter <= 0;
            end
        end
    end

endmodule