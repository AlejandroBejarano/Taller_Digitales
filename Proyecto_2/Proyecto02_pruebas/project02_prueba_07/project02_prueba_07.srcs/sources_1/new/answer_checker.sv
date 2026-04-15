// =============================================================================
// answer_checker.sv — Validador de respuestas del jugador PC
//
// Monitorea la uart_interface buscando un nuevo byte recibido (new_rx_flag).
// Cuando detecta uno, lee el byte, verifica si es A/B/C/D, y lo compara
// contra la tabla de respuestas correctas para la pregunta actual.
//
// Tabla de respuestas correctas (derivada del análisis de .coe):
//   Q0=C, Q1=B, Q2=A, Q3=A, Q4=C, Q5=B, Q6=B, Q7=D, Q8=D, Q9=A
//
// Interfaz con uart_interface:
//   - Lee addr=2'b00 para verificar new_rx_flag (bit 1 del registro de control).
//   - Lee addr=2'b11 para obtener el byte recibido (registro RX).
//   - Escribe addr=2'b00 con wdata[1]=0 para limpiar new_rx_flag.
//
// Entradas:
//   clk_i           – Reloj de sistema (16 MHz).
//   rst_i           – Reset activo alto.
//   enable_i        – 1 = monitorear puerto UART; 0 = ignorar (evita capturas fuera de turno).
//   question_idx_i  – Índice de la pregunta activa (0-9); define cuál es la respuesta correcta.
//   uart_rdata_i    – Lectura del bus UART (mux externo la provee según uart_addr_o).
//
// Salidas:
//   answer_valid_o  – Pulso de 1 ciclo: se recibió A/B/C/D.
//   answer_correct_o– Nivel: la letra recibida coincide con la respuesta correcta.
//   answer_letter_o – Byte ASCII recibido ('A'=0x41 … 'D'=0x44).
//   answer_invalid_o– Pulso: byte recibido que NO es A/B/C/D.
//   uart_we_o       – Habilitación de escritura hacia uart_interface.
//   uart_addr_o     – Dirección de registro UART (00=ctrl, 11=rx).
//   uart_wdata_o    – Dato de escritura (limpia new_rx_flag en S_CLEAR_FLAG).
//
// FSM (state_t):
//   S_IDLE        – Espera enable_i para comenzar.
//   S_POLL_RX     – Lee ctrl reg (addr=00) buscando new_rx_flag (bit 1).
//   S_READ_BYTE   – Apunta a addr=11 (reg RX) para una lectura con latencia.
//   S_CAPTURE_BYTE– Captura el dato leído (1 ciclo de latencia de BRAM).
//   S_CLEAR_FLAG  – Escribe 0 en ctrl reg para limpiar new_rx_flag.
//   S_VALIDATE    – Verifica si el byte es A/B/C/D y compara con respuesta correcta.
// =============================================================================
`timescale 1ns / 1ps

module answer_checker (
    input  logic        clk_i,
    input  logic        rst_i,

    // Control
    input  logic        enable_i,          // 1 = escuchar respuestas, 0 = ignorar
    input  logic [3:0]  question_idx_i,    // Índice de pregunta actual (0-9)
    output logic        answer_valid_o,    // Pulso: se recibió una respuesta válida (A/B/C/D)
    output logic        answer_correct_o,  // 1 = respuesta correcta, 0 = incorrecta
    output logic [7:0]  answer_letter_o,   // Letra recibida (ASCII: 'A','B','C','D')
    output logic        answer_invalid_o,  // Pulso: se recibió un byte no válido

    // Bus hacia uart_interface (salidas del MUX)
    output logic        uart_we_o,
    output logic [1:0]  uart_addr_o,
    output logic [31:0] uart_wdata_o,
    input  logic [31:0] uart_rdata_i       // Lectura de registros UART
);

    // =========================================================================
    // Función: obtener respuesta correcta para cada pregunta (LUT sintetizable)
    // Retorna el ASCII de la letra correcta según el índice de pregunta.
    // =========================================================================
    function automatic logic [7:0] get_correct_answer(input logic [3:0] idx);
        case (idx)
            4'd0:    get_correct_answer = 8'h43; // C
            4'd1:    get_correct_answer = 8'h42; // B
            4'd2:    get_correct_answer = 8'h41; // A
            4'd3:    get_correct_answer = 8'h41; // A
            4'd4:    get_correct_answer = 8'h43; // C
            4'd5:    get_correct_answer = 8'h42; // B
            4'd6:    get_correct_answer = 8'h42; // B
            4'd7:    get_correct_answer = 8'h44; // D
            4'd8:    get_correct_answer = 8'h44; // D
            4'd9:    get_correct_answer = 8'h41; // A
            default: get_correct_answer = 8'h00; // Inválido
        endcase
    endfunction

    // =========================================================================
    // FSM States
    // =========================================================================
    typedef enum logic [2:0] {
        S_IDLE,
        S_POLL_RX,         // Leer registro de control para verificar new_rx
        S_READ_BYTE,       // Leer byte recibido en addr=11
        S_CAPTURE_BYTE,    // Capturar el byte (1 ciclo de latencia de lectura)
        S_CLEAR_FLAG,      // Limpiar new_rx_flag
        S_VALIDATE         // Validar respuesta
    } state_t;

    state_t state;
    logic [7:0] rx_byte;          // Byte recibido del jugador PC
    logic [7:0] correct_answer;   // Respuesta correcta para la pregunta activa

    // =========================================================================
    // Salidas del bus UART (combinacionales según estado FSM)
    // =========================================================================
    always_comb begin
        uart_we_o    = 1'b0;
        uart_addr_o  = 2'b00;
        uart_wdata_o = 32'b0;

        case (state)
            S_POLL_RX: begin
                uart_we_o    = 1'b0;
                uart_addr_o  = 2'b00;   // Leer registro de control (bit 1 = new_rx_flag)
            end
            S_READ_BYTE: begin
                uart_we_o    = 1'b0;
                uart_addr_o  = 2'b11;   // Apuntar a registro RX
            end
            S_CAPTURE_BYTE: begin
                uart_we_o    = 1'b0;
                uart_addr_o  = 2'b11;   // Mantener dirección para que dato sea estable
            end
            S_CLEAR_FLAG: begin
                uart_we_o    = 1'b1;
                uart_addr_o  = 2'b00;           // Escribir registro de control
                uart_wdata_o = 32'h0000_0000;   // bit 1 = 0 => limpiar new_rx_flag
            end
            default: ;
        endcase
    end

    // =========================================================================
    // FSM secuencial
    // =========================================================================
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state            <= S_IDLE;
            rx_byte          <= 8'h00;
            correct_answer   <= 8'h00;
            answer_valid_o   <= 1'b0;
            answer_correct_o <= 1'b0;
            answer_letter_o  <= 8'h00;
            answer_invalid_o <= 1'b0;
        end else begin
            // Defaults: pulsos duran 1 ciclo
            answer_valid_o   <= 1'b0;
            answer_invalid_o <= 1'b0;

            case (state)

                S_IDLE: begin
                    if (enable_i) begin
                        // Pre-calcular respuesta correcta al entrar a la ronda
                        correct_answer <= get_correct_answer(question_idx_i);
                        state <= S_POLL_RX;
                    end
                end

                S_POLL_RX: begin
                    if (!enable_i) begin
                        state <= S_IDLE;      // Si se desactiva, volver a IDLE
                    end else if (uart_rdata_i[1] == 1'b1) begin
                        // new_rx_flag activo: hay byte disponible para leer
                        state <= S_READ_BYTE;
                    end
                    // Si no hay byte nuevo, seguir polling
                end

                S_READ_BYTE: begin
                    // Apuntar a addr=11; se necesita 1 ciclo de latencia antes de capturar
                    state <= S_CAPTURE_BYTE;
                end

                S_CAPTURE_BYTE: begin
                    // El dato de addr=11 ya está disponible en uart_rdata_i
                    rx_byte <= uart_rdata_i[7:0];
                    state   <= S_CLEAR_FLAG;
                end

                S_CLEAR_FLAG: begin
                    // Se escribe 0 en ctrl para liberar new_rx_flag
                    state <= S_VALIDATE;
                end

                S_VALIDATE: begin
                    // Verificar si el byte recibido es A (0x41), B (0x42), C (0x43) o D (0x44)
                    if (rx_byte == 8'h41 || rx_byte == 8'h42 ||
                        rx_byte == 8'h43 || rx_byte == 8'h44) begin
                        answer_valid_o  <= 1'b1;
                        answer_letter_o <= rx_byte;
                        // Comparar con respuesta correcta pre-calculada al inicio de la ronda
                        answer_correct_o <= (rx_byte == correct_answer);
                    end else begin
                        // Byte no válido: no es A/B/C/D (ej. retorno de carro, espacio)
                        answer_invalid_o <= 1'b1;
                    end
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
