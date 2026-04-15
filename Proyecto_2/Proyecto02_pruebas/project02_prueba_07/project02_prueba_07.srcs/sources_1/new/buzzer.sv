// =============================================================================
// buzzer.sv — Generador de tonos PWM para retroalimentación sonora
//
// Genera una onda cuadrada de frecuencia fija durante 1 segundo cuando
// recibe un pulso de comando. El tono depende del resultado de la ronda:
//   play_ok_i  → 1000 Hz (tono agudo de victoria)
//   play_err_i → 300 Hz  (tono grave de error/timeout)
//
// Si ambos pulsos llegan en el mismo ciclo, play_ok_i tiene prioridad.
//
// Entradas:
//   clk_i      – Reloj de 16 MHz.
//   rst_i      – Reset activo alto.
//   play_ok_i  – Pulso de 1 ciclo: respuesta correcta → tono WIN.
//   play_err_i – Pulso de 1 ciclo: respuesta incorrecta / timeout → tono ERR.
//
// Salidas:
//   buzzer_o   – Onda cuadrada al pin del Pmod (buzzer piezoeléctrico pasivo).
//
// Parámetros internos:
//   WIN_TOP    – Medio-período del tono de victoria en ciclos de 16 MHz.
//   ERR_TOP    – Medio-período del tono de error en ciclos de 16 MHz.
//   DURATION   – Duración del tono: 1 s = 16,000,000 ciclos a 16 MHz.
//
// Variables internas:
//   duration_cnt – Contador de ciclos durante los que suena el buzzer.
//   tone_cnt     – Contador de ciclos dentro del medio-período actual.
//   tone_top     – Medio-período activo (WIN_TOP o ERR_TOP, latched al inicio).
//   playing      – Flag: 1 mientras el buzzer está activo.
// =============================================================================
`timescale 1ns / 1ps

module buzzer (
    input  logic clk_i,       // Reloj sistema 16 MHz
    input  logic rst_i,
    input  logic play_ok_i,   // Pulso: Acertaron → tono 1000 Hz
    input  logic play_err_i,  // Pulso: Fallaron / Timeout → tono 300 Hz
    output logic buzzer_o     // Salida de la onda cuadrada al pin del Pmod
);

    // Frecuencias:
    // WIN: 1000 Hz -> Período = 1 ms -> Medio período = 0.5 ms -> 8000 ciclos a 16 MHz
    // ERR: 300 Hz  -> Período = 3.33 ms -> Medio período = 1.66 ms -> 26666 ciclos a 16 MHz
    
    localparam int WIN_TOP = 8000;
    localparam int ERR_TOP = 26666;
    
    // Tono dura 1 segundo -> 16,000,000 ciclos
    localparam int DURATION = 16_000_000;

    logic [24:0] duration_cnt;
    logic [15:0] tone_cnt;
    logic [15:0] tone_top;
    logic        playing;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            duration_cnt <= '0;
            tone_cnt     <= '0;
            tone_top     <= '0;
            playing      <= 1'b0;
            buzzer_o     <= 1'b0;
        end else begin
            if (play_ok_i) begin
                playing      <= 1'b1;
                duration_cnt <= '0;
                tone_top     <= WIN_TOP[15:0];
            end else if (play_err_i) begin
                playing      <= 1'b1;
                duration_cnt <= '0;
                tone_top     <= ERR_TOP[15:0];
            end
            
            if (playing) begin
                if (duration_cnt == DURATION) begin
                    playing  <= 1'b0;
                    buzzer_o <= 1'b0;
                end else begin
                    duration_cnt <= duration_cnt + 1;
                    
                    if (tone_cnt >= tone_top) begin
                        tone_cnt <= '0;
                        buzzer_o <= ~buzzer_o;
                    end else begin
                        tone_cnt <= tone_cnt + 1;
                    end
                end
            end else begin
                buzzer_o <= 1'b0;
            end
        end
    end

endmodule
