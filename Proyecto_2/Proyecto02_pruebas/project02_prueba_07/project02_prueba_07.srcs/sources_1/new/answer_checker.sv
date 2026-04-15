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
//   - Lee addr=2'b00 para verificar new_rx_flag (bit 1)
//   - Lee addr=2'b11 para obtener el byte recibido
//   - Escribe addr=2'b00 con wdata[1]=0 para limpiar new_rx_flag
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
    logic [7:0] rx_byte;
    logic [7:0] correct_answer;

    // =========================================================================
    // Salidas del bus UART (combinacionales)
    // =========================================================================
    always_comb begin
        uart_we_o    = 1'b0;
        uart_addr_o  = 2'b00;
        uart_wdata_o = 32'b0;

        case (state)
            S_POLL_RX: begin
                uart_we_o    = 1'b0;
                uart_addr_o  = 2'b00;   // Leer registro de control
            end
            S_READ_BYTE: begin
                uart_we_o    = 1'b0;
                uart_addr_o  = 2'b11;   // Leer registro RX
            end
            S_CAPTURE_BYTE: begin
                uart_we_o    = 1'b0;
                uart_addr_o  = 2'b11;   // Mantener lectura de RX
            end
            S_CLEAR_FLAG: begin
                uart_we_o    = 1'b1;
                uart_addr_o  = 2'b00;   // Escribir registro de control
                uart_wdata_o = 32'h0000_0000; // bit 1 = 0 => limpiar new_rx
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
                        // Pre-calcular respuesta correcta al entrar
                        correct_answer <= get_correct_answer(question_idx_i);
                        state <= S_POLL_RX;
                    end
                end

                S_POLL_RX: begin
                    if (!enable_i) begin
                        state <= S_IDLE;
                    end else if (uart_rdata_i[1] == 1'b1) begin
                        // new_rx_flag está activo: hay byte disponible
                        state <= S_READ_BYTE;
                    end
                    // Si no hay byte, seguir polling
                end

                S_READ_BYTE: begin
                    // Pedir lectura de addr=11, esperar 1 ciclo de latencia
                    state <= S_CAPTURE_BYTE;
                end

                S_CAPTURE_BYTE: begin
                    // Capturar el dato leído
                    rx_byte <= uart_rdata_i[7:0];
                    state   <= S_CLEAR_FLAG;
                end

                S_CLEAR_FLAG: begin
                    // Limpiar new_rx_flag escribiendo 0 en bit 1 del control
                    state <= S_VALIDATE;
                end

                S_VALIDATE: begin
                    // Verificar si el byte es A, B, C o D
                    if (rx_byte == 8'h41 || rx_byte == 8'h42 ||
                        rx_byte == 8'h43 || rx_byte == 8'h44) begin
                        answer_valid_o  <= 1'b1;
                        answer_letter_o <= rx_byte;
                        // Comparar con respuesta correcta (pre-calculada)
                        answer_correct_o <= (rx_byte == correct_answer);
                    end else begin
                        // Byte no válido (no es A/B/C/D)
                        answer_invalid_o <= 1'b1;
                    end
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
