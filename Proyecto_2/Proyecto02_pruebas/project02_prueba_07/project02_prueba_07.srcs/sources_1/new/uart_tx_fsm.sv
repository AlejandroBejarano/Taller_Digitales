// =============================================================================
// uart_tx_fsm.sv — FSM de transmisión serial de preguntas y opciones
//
// Lee datos de las ROMs de preguntas (32 bytes) y respuestas (32 bytes)
// byte a byte y los envía por la uart_interface con bytes de protocolo
// intercalados (SOH, STX, ETX).
//
// Protocolo de envío por ronda:
//   [0x01 (SOH)][question_idx][32 bytes pregunta][0x02 (STX)][32 bytes opciones][0x03 (ETX)]
//
// Interfaz con uart_interface via bus estándar de 32 bits:
//   - Escribe dato en addr=2'b10 (tx_reg).
//   - Activa send en addr=2'b00 (ctrl_reg bit 0).
//   - Lee addr=2'b00 para verificar que send_pending=0 (transmisión completa).
//
// Entradas:
//   clk_i           – Reloj de sistema (16 MHz).
//   rst_i           – Reset activo alto.
//   start_i         – Pulso de 1 ciclo: iniciar transmisión de la pregunta.
//   question_idx_i  – Índice de la pregunta (0-9); define las direcciones base en ROM.
//   uart_rdata_i    – Bus de lectura UART (para polling de send_pending).
//   rom_q_data_i    – Dato leído de ROM de preguntas (latencia 1 ciclo).
//   rom_a_data_i    – Dato leído de ROM de respuestas (latencia 1 ciclo).
//
// Salidas:
//   done_o          – Pulso: toda la secuencia fue enviada.
//   busy_o          – Nivel: módulo ocupado.
//   rom_q_addr_o    – Dirección de lectura en ROM de preguntas (base + byte_counter).
//   rom_a_addr_o    – Dirección de lectura en ROM de respuestas (base + byte_counter).
//   uart_we_o       – Habilitación de escritura UART.
//   uart_addr_o     – Dirección de registro UART.
//   uart_wdata_o    – Dato a escribir en registro UART.
//
// FSM (state_t):
//   S_IDLE          – Espera pulso start_i; calcula direcciones base.
//   S_SEND_SOH      – Prepara byte 0x01 y va a sub-rutina de envío.
//   S_SEND_QIDX     – Prepara byte con el índice de la pregunta.
//   S_ROM_Q_WAIT    – Ciclo de latencia de ROM de preguntas.
//   S_SEND_Q_BYTE   – Envía byte de texto de pregunta leído de ROM.
//   S_SEND_STX      – Prepara byte 0x02 (separador pregunta/opciones).
//   S_ROM_A_WAIT    – Ciclo de latencia de ROM de respuestas.
//   S_SEND_A_BYTE   – Envía byte de opciones leído de ROM.
//   S_SEND_ETX      – Prepara byte 0x03 (fin, PC puede responder).
//   S_WRITE_TX      – Sub-rutina: escribe byte en registro TX de uart_interface.
//   S_TRIGGER_SEND  – Sub-rutina: activa bit send en ctrl.
//   S_WAIT_SEND_LATCH – Sub-rutina: espera 1 ciclo de propagación.
//   S_WAIT_SEND_DONE  – Sub-rutina: polling send_pending=0.
//   S_DONE          – Señaliza done_o=1 por 1 ciclo.
// =============================================================================
`timescale 1ns / 1ps

module uart_tx_fsm (
    input  logic        clk_i,
    input  logic        rst_i,

    // Control
    input  logic        start_i,           // Pulso: iniciar transmisión de pregunta
    input  logic [3:0]  question_idx_i,    // Índice de pregunta (0-9)
    output logic        done_o,            // Pulso: transmisión completada
    output logic        busy_o,            // 1 mientras está transmitiendo

    // Interfaz hacia ROM de preguntas
    output logic [8:0]  rom_q_addr_o,      // Dirección ROM preguntas (0-319)
    input  logic [7:0]  rom_q_data_i,      // Dato leído de ROM preguntas

    // Interfaz hacia ROM de respuestas
    output logic [8:0]  rom_a_addr_o,      // Dirección ROM respuestas (0-319)
    input  logic [7:0]  rom_a_data_i,      // Dato leído de ROM respuestas

    // Bus hacia uart_interface (salidas del MUX)
    output logic        uart_we_o,
    output logic [1:0]  uart_addr_o,
    output logic [31:0] uart_wdata_o,
    input  logic [31:0] uart_rdata_i       // Para leer send_pending (bit 0 del ctrl)
);

    // =========================================================================
    // Constantes de protocolo
    // =========================================================================
    localparam [7:0] SOH = 8'h01;  // Start of Header (inicio pregunta)
    localparam [7:0] STX = 8'h02;  // Start of Text (inicio opciones)
    localparam [7:0] ETX = 8'h03;  // End of Text (fin; PC puede responder)

    localparam int BYTES_PER_QUESTION = 32;
    localparam int BYTES_PER_ANSWERS  = 32;

    // =========================================================================
    // FSM States
    // =========================================================================
    typedef enum logic [3:0] {
        S_IDLE,
        S_SEND_SOH,
        S_SEND_QIDX,
        S_ROM_Q_WAIT,
        S_SEND_Q_BYTE,
        S_SEND_STX,
        S_ROM_A_WAIT,
        S_SEND_A_BYTE,
        S_SEND_ETX,
        S_WRITE_TX,
        S_TRIGGER_SEND,
        S_WAIT_SEND_LATCH,
        S_WAIT_SEND_DONE,
        S_DONE
    } state_t;

    state_t state, return_state;

    // =========================================================================
    // Registros internos
    // =========================================================================
    logic [7:0]  byte_to_send;     // Byte actual a transmitir
    logic [5:0]  byte_counter;     // Contador de bytes (0-31)
    logic [8:0]  base_addr_q;      // Dirección base pregunta = question_idx * 32
    logic [8:0]  base_addr_a;      // Dirección base respuestas = question_idx * 32

    // =========================================================================
    // Direcciones de ROM (combinacionales: base + offset del contador de bytes)
    // =========================================================================
    assign rom_q_addr_o = base_addr_q + {3'b0, byte_counter};
    assign rom_a_addr_o = base_addr_a + {3'b0, byte_counter};

    // =========================================================================
    // Salidas del bus UART (combinacionales según estado FSM)
    // =========================================================================
    always_comb begin
        uart_we_o    = 1'b0;
        uart_addr_o  = 2'b00;
        uart_wdata_o = 32'b0;

        case (state)
            S_WRITE_TX: begin
                uart_we_o    = 1'b1;
                uart_addr_o  = 2'b10;                    // Registro TX
                uart_wdata_o = {24'b0, byte_to_send};
            end
            S_TRIGGER_SEND: begin
                uart_we_o    = 1'b1;
                uart_addr_o  = 2'b00;                    // Registro control
                uart_wdata_o = 32'h0000_0001;             // bit 0 = send
            end
            S_WAIT_SEND_LATCH: begin
                uart_we_o    = 1'b0;
                uart_addr_o  = 2'b00;                    // Leer ctrl para polling
            end
            S_WAIT_SEND_DONE: begin
                uart_we_o    = 1'b0;
                uart_addr_o  = 2'b00;                    // Leer ctrl para polling
            end
            default: ;
        endcase
    end

    // =========================================================================
    // Señales de estado
    // =========================================================================
    assign busy_o = (state != S_IDLE);
    assign done_o = (state == S_DONE);

    // =========================================================================
    // FSM secuencial
    // =========================================================================
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state        <= S_IDLE;
            return_state <= S_IDLE;
            byte_to_send <= 8'h00;
            byte_counter <= 6'd0;
            base_addr_q  <= 9'd0;
            base_addr_a  <= 9'd0;
        end else begin
            case (state)

                S_IDLE: begin
                    if (start_i) begin
                        // Calcular direcciones base: question_idx << 5 = question_idx * 32
                        base_addr_q  <= {question_idx_i, 5'b0_0000};
                        base_addr_a  <= {question_idx_i, 5'b0_0000};
                        byte_counter <= 6'd0;
                        state        <= S_SEND_SOH;
                    end
                end

                // Enviar SOH (0x01): marca inicio del mensaje de pregunta
                S_SEND_SOH: begin
                    byte_to_send <= SOH;
                    return_state <= S_SEND_QIDX;
                    state        <= S_WRITE_TX;
                end

                // Enviar índice de pregunta (1 byte): permite al PC identificar la pregunta
                S_SEND_QIDX: begin
                    byte_to_send <= {4'b0, question_idx_i};
                    return_state <= S_ROM_Q_WAIT;
                    byte_counter <= 6'd0;
                    state        <= S_WRITE_TX;
                end

                // Esperar 1 ciclo de latencia de la ROM de preguntas
                S_ROM_Q_WAIT: begin
                    state <= S_SEND_Q_BYTE;
                end

                // Enviar byte de pregunta leído de ROM; repetir 32 veces
                S_SEND_Q_BYTE: begin
                    byte_to_send <= rom_q_data_i;
                    if (byte_counter == BYTES_PER_QUESTION - 1) begin
                        return_state <= S_SEND_STX;  // Último byte: continuar con STX
                        byte_counter <= 6'd0;
                    end else begin
                        return_state <= S_ROM_Q_WAIT; // Más bytes: incrementar y releer
                        byte_counter <= byte_counter + 1;
                    end
                    state <= S_WRITE_TX;
                end

                // Enviar STX (0x02): separador entre pregunta y opciones
                S_SEND_STX: begin
                    byte_to_send <= STX;
                    return_state <= S_ROM_A_WAIT;
                    byte_counter <= 6'd0;
                    state        <= S_WRITE_TX;
                end

                // Esperar 1 ciclo de latencia de la ROM de respuestas
                S_ROM_A_WAIT: begin
                    state <= S_SEND_A_BYTE;
                end

                // Enviar byte de opciones leído de ROM; repetir 32 veces
                S_SEND_A_BYTE: begin
                    byte_to_send <= rom_a_data_i;
                    if (byte_counter == BYTES_PER_ANSWERS - 1) begin
                        return_state <= S_SEND_ETX;
                        byte_counter <= 6'd0;
                    end else begin
                        return_state <= S_ROM_A_WAIT;
                        byte_counter <= byte_counter + 1;
                    end
                    state <= S_WRITE_TX;
                end

                // Enviar ETX (0x03): fin del mensaje; PC puede enviar respuesta ahora
                S_SEND_ETX: begin
                    byte_to_send <= ETX;
                    return_state <= S_DONE;
                    state        <= S_WRITE_TX;
                end

                // ----- Sub-rutina de envío UART -----
                // 1. S_WRITE_TX: coloca byte_to_send en registro TX vía lógica comb
                S_WRITE_TX: begin
                    state <= S_TRIGGER_SEND;
                end

                // 2. S_TRIGGER_SEND: activa bit send en ctrl; UART empieza a serializar
                S_TRIGGER_SEND: begin
                    state <= S_WAIT_SEND_LATCH;
                end

                // 3. S_WAIT_SEND_LATCH: espera 1 ciclo para que send_pending se estabilice
                S_WAIT_SEND_LATCH: begin
                    state <= S_WAIT_SEND_DONE;
                end

                // 4. S_WAIT_SEND_DONE: polling hasta que send_pending=0 (byte serializado)
                S_WAIT_SEND_DONE: begin
                    if (uart_rdata_i[0] == 1'b0) begin
                        state <= return_state;  // Volver al estado que solicitó el envío
                    end
                end

                // Transmisión completa; done_o=1 por 1 ciclo
                S_DONE: begin
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
