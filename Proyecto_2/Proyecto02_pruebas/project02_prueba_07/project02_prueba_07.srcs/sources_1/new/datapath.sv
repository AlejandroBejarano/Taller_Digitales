// =============================================================================
// datapath.sv — Colección de módulos de control y juego para Jeopardy
//
// Contiene los siguientes sub-módulos:
//   LFSR            – Generador de secuencia pseudo-aleatoria de N bits.
//   thirty_sec_timer– Timer de 30 segundos con pulso de salida (no usado en top actual).
//   timeCounter     – Árbitro de tiempo entre dos jugadores (quién respondió primero).
//   random_number   – Filtra la salida del LFSR para valores 0-9.
//   question_selector – Selecciona pregunta no repetida, lleva conteo de 7 rondas.
// =============================================================================
`timescale 1ns / 1ps

// =============================================================================
// LFSR — Linear Feedback Shift Register de NUM_BITS bits
//
// Genera una secuencia pseudoaleatoria de período 2^NUM_BITS - 1.
// Implementado con realimentación XNOR en los bits MSB y LSB del registro.
//
// Entradas:
//   clk          – Reloj de sistema.
//   rst          – Reset: carga i_Seed_Data en el registro.
//   enable       – 1 = avanzar la secuencia cada ciclo.
//   i_Seed_Data  – Valor inicial del LFSR (no debe ser 0).
//
// Salidas:
//   o_LFSR_Data  – Valor actual de los NUM_BITS bits del registro.
//   o_LFSR_Done  – 1 cuando el registro ha vuelto al valor semilla (ciclo completo).
// =============================================================================
module LFSR #(parameter NUM_BITS = 4) (
   input  logic clk,
   input  logic rst,
   input  logic enable,
   input  logic [NUM_BITS-1:0] i_Seed_Data,
   output logic [NUM_BITS-1:0] o_LFSR_Data,
   output logic o_LFSR_Done
);
  logic [NUM_BITS:1] r_LFSR;
  logic              r_XNOR;

  always_ff @(posedge clk) begin
    if (rst) begin
        r_LFSR <= i_Seed_Data;
    end else if (enable == 1'b1) begin
        // Desplazamiento: el bit nuevo entra por la derecha (bit 1)
        r_LFSR <= {r_LFSR[NUM_BITS-1:1], r_XNOR};
    end
  end

  always_comb begin
      case (NUM_BITS)
        // Polinomio x^4 + x^3 + 1 (XNOR de MSB y MSB-1)
        4: r_XNOR = r_LFSR[4] ^~ r_LFSR[3];
        default: r_XNOR = 0;
      endcase
  end

  assign o_LFSR_Data = r_LFSR[NUM_BITS:1];
  // Señal de ciclo completo: el LFSR volvió a la semilla
  assign o_LFSR_Done = (r_LFSR[NUM_BITS:1] == i_Seed_Data) ? 1'b1 : 1'b0;
endmodule

// =============================================================================
// thirty_sec_timer — Timer de 30 segundos (módulo auxiliar, no usado en top actual)
//
// Genera un pulso de 1 ciclo (rst_i) al completar 30 segundos.
// A 16 MHz: 16,000,000 × 30 = 480,000,000 ciclos.
//
// Entradas:
//   clk      – Reloj de 16 MHz.
//   rst      – Reset asíncrono.
//   enable_i – 1 = contando; 0 = contador en 0.
//
// Salidas:
//   rst_i    – Pulso de 1 ciclo al cumplir 30 segundos.
// =============================================================================
module thirty_sec_timer(
    input  logic clk,
    input  logic rst,
    input  logic enable_i,
    output logic rst_i //30 seconds pulse
);
    // Para 16 MHz y 30 segundos = 480,000,000 ciclos
    localparam int CNT_MAX = (16_000_000 * 30) - 1;
    logic [28:0] counter;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= 0;
            rst_i   <= 0;
        end else begin
            if (enable_i) begin
                if (counter == CNT_MAX) begin
                    counter <= 0;
                    rst_i   <= 1;  // Pulso de 1 ciclo al completar 30 s
                end else begin
                    counter <= counter + 1;
                    rst_i   <= 0;
                end
            end else begin
                counter <= 0;
                rst_i   <= 0;
            end
        end
    end
endmodule

// =============================================================================
// timeCounter — Árbitro de tiempo: determina quién respondió primero
//
// Dos contadores independientes miden cuántos ciclos tardó cada jugador
// (A = FPGA, B = PC) en responder (enviar su señal tA / tB). El jugador
// que acumuló MENOS ciclos gana. Si ninguno respondió, no hay ganador.
//
// Entradas:
//   clk   – Reloj de sistema.
//   rst   – Reset asíncrono.
//   rst_i – Reset sincrónico (fin de ronda): reinicia contadores y locks.
//   tA    – Pulso: jugador A respondió (lo bloquea para no sobreescribir).
//   tB    – Pulso: jugador B respondió.
//
// Salidas:
//   time_tie – 1 si ambos respondieron en el mismo ciclo.
//   tA_1     – 1 si el jugador A fue el más rápido.
//   tB_1     – 1 si el jugador B fue el más rápido.
// =============================================================================
module timeCounter(
    input  logic clk,
    input  logic rst,
    input  logic rst_i,
    input  logic tA,
    input  logic tB,
    output logic time_tie,
    output logic tA_1,
    output logic tB_1
);
    logic [31:0] counterA;   // Ciclos transcurridos antes de que A respondiera
    logic [31:0] counterB;
    logic lockedA, lockedB;  // Cuando el jugador responde, su contador se congela

    // Contador para el jugador A
    always_ff @(posedge clk or posedge rst) begin
        if (rst || rst_i) begin
            counterA <= 0;
            lockedA  <= 0;
        end else if (tA && !lockedA) begin
            lockedA  <= 1;           // Congelar al momento de la respuesta
        end else if (!lockedA) begin
            counterA <= counterA + 1; // Acumular tiempo mientras no responde
        end
    end

    // Contador para el jugador B
    always_ff @(posedge clk or posedge rst) begin
        if (rst || rst_i) begin
            counterB <= 0;
            lockedB  <= 0;
        end else if (tB && !lockedB) begin
            lockedB  <= 1;
        end else if (!lockedB) begin
            counterB <= counterB + 1;
        end
    end

    // Lógica de arbitraje combinacional
    always_comb begin
        tA_1     = 0;
        tB_1     = 0;
        time_tie = 0;
        if (lockedA && lockedB) begin
            // Ambos respondieron: comparar tiempos
            if (counterA < counterB)
                tA_1 = 1;
            else if (counterB < counterA)
                tB_1 = 1;
            else
                time_tie = 1;
        end else if (lockedA) begin
            tA_1 = 1;   // Solo A respondió
        end else if (lockedB) begin
            tB_1 = 1;   // Solo B respondió
        end
    end
endmodule

// =============================================================================
// random_number — Filtra la salida del LFSR para el rango 0-9
//
// Recibe el valor del LFSR (0-15) y solo propaga si está en 0-9,
// pues las preguntas tienen índices 0 a 9.
//
// Entradas:
//   clk       – Reloj de sistema.
//   rst       – Reset asíncrono.
//   enable    – 1 = evaluar lfsr_out cada ciclo.
//   lfsr_out  – Valor de 4 bits del LFSR.
//
// Salidas:
//   number    – Índice válido 0-9 resultado del filtro.
//   valid     – Pulso de 1 ciclo: number contiene un valor usable.
// =============================================================================
module random_number (
    input  logic clk,
    input  logic rst,
    input  logic enable,
    input  logic [3:0] lfsr_out,
    output logic [3:0] number,
    output logic valid
);
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            number <= 4'd1;
            valid  <= 0;
        end else if (enable) begin
            valid <= 0;
            // Solo dejamos pasar de 0 a 9 (índices válidos para memoria)
            if (lfsr_out <= 4'd9) begin
                number <= lfsr_out;
                valid  <= 1;
            end
            // Valores 10-15 son descartados; el LFSR seguirá avanzando
        end
    end
endmodule

// =============================================================================
// question_selector — Selecciona preguntas únicas; lleva conteo de 7 rondas
//
// Mantiene un bitmap (used_mask) de 10 bits para saber qué preguntas ya
// fueron seleccionadas. Cuando random_number produce un índice libre, lo
// acepta y emite ready. Cuando se han seleccionado 7 preguntas, round_done=1.
//
// Entradas:
//   clk     – Reloj de sistema.
//   rst     – Reset asíncrono.
//   enable  – 1 = evaluar number/valid cada ciclo.
//   number  – Índice propuesto por random_number (0-9).
//   valid   – Pulso: number es válido.
//
// Salidas:
//   question_index – Índice aceptado (el que se usará en la ronda).
//   ready          – Pulso de 1 ciclo: question_index es válido y fue aceptado.
//   round_done     – Nivel: ya se seleccionaron 7 preguntas (partida completa).
// =============================================================================
module question_selector (
    input  logic clk,
    input  logic rst,
    input  logic enable,
    input  logic [3:0] number,
    input  logic       valid,

    output logic [3:0] question_index,
    output logic ready,
    output logic round_done      // high when 7 questions have been picked
);
    logic [9:0] used_mask;   // Bit i = 1 si la pregunta i ya fue usada
    logic [2:0] pick_count;  // Cuántas preguntas únicas se han seleccionado

    assign round_done = (pick_count == 7);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            question_index <= 0;
            ready          <= 0;
            used_mask      <= 10'b0;
            pick_count     <= 0;
        end else begin
            ready <= 0;
            if (enable && valid && !round_done) begin
                if (!used_mask[number]) begin
                    // La pregunta no fue usada: aceptar
                    used_mask[number] <= 1;
                    question_index    <= number;
                    ready             <= 1;
                    pick_count        <= pick_count + 1;
                end
                // Si ya fue usada, descartar; el LFSR avanzará al siguiente ciclo
            end
        end
    end
endmodule
