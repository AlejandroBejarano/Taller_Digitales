/**
 * UART Controller
 * ----------------
 * Controla el envío del índice de una pregunta seleccionada a través de UART.
 * Entradas:
 *   - clk: reloj del sistema
 *   - rst: reset síncrono
 *   - new_question: pulso que indica que se debe enviar una nueva pregunta
 *   - question_selected: índice (1-10) de la pregunta seleccionada
 *   - written: pulso de confirmación de transmisión UART
 * Salidas:
 *   - we: pulso one-shot para activar la transmisión UART
 *   - w_data: dato a transmitir (índice de la pregunta)
 *
 * Funcionamiento:
 *   - Cuando new_question se activa, el módulo envía el valor de question_selected por UART,
 *     generando un pulso we de un ciclo. Espera la confirmación de written antes de aceptar
 *     otro envío.
 */
module uart_controller (
    input  logic       clk,              // Reloj del sistema
    input  logic       rst,              // Reset síncrono
    input  logic       new_question,     // Pulso para nueva pregunta
    input  logic [7:0] question_selected,// Índice de la pregunta seleccionada
    output logic       we,               // Pulso de escritura UART
    input  logic       written,          // Pulso de confirmación UART
    output logic [7:0] w_data            // Dato a transmitir
);




// Máquina de estados para controlar el envío UART
typedef enum logic [1:0] {
    IDLE,   // Espera nueva pregunta
    LOAD,   // Carga el dato a enviar
    WE,     // Pulso de escritura UART
    WAIT    // Espera confirmación de transmisión
} state_t;

state_t state;

always_ff @(posedge clk) begin
    if (rst) begin
        we    <= 0;
        state <= IDLE;
    end else begin
        case (state)
            IDLE: begin
                we <= 0;
                if (new_question)
                    state <= LOAD;
            end
            LOAD: begin
                w_data <= question_selected;
                state  <= WE;
            end
            WE: begin
                we    <= 1;
                state <= WAIT;
            end
            WAIT: begin
                we <= 0;
                if (written)
                    state <= IDLE;
            end
            default: state <= IDLE;
        endcase
    end
end

uart_interface uart_if (
    .clk_i   (clk),
    .rst_i   (rst),
    .we_i    (we),
    .addr_i  (2'b10), // Dirección fija para el registro de transmisión
    .wdata_i (w_data_i), // Solo se envía un byte
    .rdata_o (rdata_o) // No se utiliza la lectura en este módulo
);



endmodule