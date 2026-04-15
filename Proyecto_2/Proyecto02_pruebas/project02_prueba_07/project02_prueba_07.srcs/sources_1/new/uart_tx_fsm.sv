// =============================================================================
// uart_tx_fsm.sv — FSM de transmisión serial de preguntas y opciones
//
// Lee datos de las ROMs de preguntas (32 bytes) y respuestas (32 bytes)
// byte a byte y los envía por la uart_interface con bytes de protocolo
// intercalados (SOH, STX, ETX).
//
// Protocolo de envío por ronda:
//   [0x01][question_idx][32 bytes pregunta][0x02][32 bytes opciones][0x03]
//
// Interfaz con uart_interface via bus estándar de 32 bits:
//   - Escribe dato en addr=2'b10 (tx_reg)
//   - Activa send en addr=2'b00 (ctrl_reg bit 0)
//   - Lee addr=2'b00 para verificar que send_pending=0 (transmisión completa)
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
    input  logic [31:0] uart_rdata_i       // Para leer send_pending (bit 0)
);

    // =========================================================================
    // Constantes de protocolo
    // =========================================================================
    localparam [7:0] SOH = 8'h01;  // Start of Header (inicio pregunta)
    localparam [7:0] STX = 8'h02;  // Start of Text (inicio opciones)
    localparam [7:0] ETX = 8'h03;  // End of Text (fin, PC puede responder)

    localparam int BYTES_PER_QUESTION = 32;
    localparam int BYTES_PER_ANSWERS  = 32;

    // =========================================================================
    // FSM States
    // =========================================================================
    typedef enum logic [3:0] {
        S_IDLE,
        S_SEND_SOH,          // Enviar byte SOH (0x01)
        S_SEND_QIDX,         // Enviar byte de índice de pregunta
        S_ROM_Q_WAIT,        // Esperar 1 ciclo de latencia de ROM preguntas
        S_SEND_Q_BYTE,       // Enviar byte de pregunta
        S_SEND_STX,          // Enviar byte STX (0x02)
        S_ROM_A_WAIT,        // Esperar 1 ciclo de latencia de ROM respuestas
        S_SEND_A_BYTE,       // Enviar byte de respuesta/opción
        S_SEND_ETX,          // Enviar byte ETX (0x03)
        S_WRITE_TX,          // Escribir byte en registro TX de uart_interface
        S_TRIGGER_SEND,      // Activar bit send en registro de control
        S_WAIT_SEND_LATCH,   // Espera 1 ciclo para que send_pending se refleje
        S_WAIT_SEND_DONE,    // Esperar que send_pending vuelva a 0
        S_DONE
    } state_t;

    state_t state, return_state;

    // =========================================================================
    // Registros internos
    // =========================================================================
    logic [7:0]  byte_to_send;     // Byte actual a transmitir
    logic [5:0]  byte_counter;     // Contador de bytes (0-31)
    logic [8:0]  base_addr_q;      // Dirección base de pregunta = idx * 32
    logic [8:0]  base_addr_a;      // Dirección base de respuestas = idx * 32

    // =========================================================================
    // Direcciones de ROM (combinacionales, basadas en base + counter)
    // =========================================================================
    assign rom_q_addr_o = base_addr_q + {3'b0, byte_counter};
    assign rom_a_addr_o = base_addr_a + {3'b0, byte_counter};

    // =========================================================================
    // Salidas del bus UART (combinacionales según estado)
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

                // =============================================================
                // IDLE: Espera el pulso de start
                // =============================================================
                S_IDLE: begin
                    if (start_i) begin
                        // Calcular direcciones base: question_idx * 32
                        base_addr_q  <= {question_idx_i, 5'b0_0000};  // idx << 5
                        base_addr_a  <= {question_idx_i, 5'b0_0000};  // idx << 5
                        byte_counter <= 6'd0;
                        state        <= S_SEND_SOH;
                    end
                end

                // =============================================================
                // Enviar SOH (0x01)
                // =============================================================
                S_SEND_SOH: begin
                    byte_to_send <= SOH;
                    return_state <= S_SEND_QIDX;
                    state        <= S_WRITE_TX;
                end

                // =============================================================
                // Enviar índice de pregunta
                // =============================================================
                S_SEND_QIDX: begin
                    byte_to_send <= {4'b0, question_idx_i};
                    return_state <= S_ROM_Q_WAIT;
                    byte_counter <= 6'd0;
                    state        <= S_WRITE_TX;
                end

                // =============================================================
                // Esperar latencia de ROM preguntas (1 ciclo)
                // =============================================================
                S_ROM_Q_WAIT: begin
                    state <= S_SEND_Q_BYTE;
                end

                // =============================================================
                // Enviar byte de pregunta desde ROM
                // =============================================================
                S_SEND_Q_BYTE: begin
                    byte_to_send <= rom_q_data_i;
                    if (byte_counter == BYTES_PER_QUESTION - 1) begin
                        return_state <= S_SEND_STX;
                        byte_counter <= 6'd0;
                    end else begin
                        return_state <= S_ROM_Q_WAIT;
                        byte_counter <= byte_counter + 1;
                    end
                    state <= S_WRITE_TX;
                end

                // =============================================================
                // Enviar STX (0x02)
                // =============================================================
                S_SEND_STX: begin
                    byte_to_send <= STX;
                    return_state <= S_ROM_A_WAIT;
                    byte_counter <= 6'd0;
                    state        <= S_WRITE_TX;
                end

                // =============================================================
                // Esperar latencia de ROM respuestas (1 ciclo)
                // =============================================================
                S_ROM_A_WAIT: begin
                    state <= S_SEND_A_BYTE;
                end

                // =============================================================
                // Enviar byte de opciones desde ROM
                // =============================================================
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

                // =============================================================
                // Enviar ETX (0x03)
                // =============================================================
                S_SEND_ETX: begin
                    byte_to_send <= ETX;
                    return_state <= S_DONE;
                    state        <= S_WRITE_TX;
                end

                // =============================================================
                // Sub-rutina de envío: Escribir byte en registro TX
                // =============================================================
                S_WRITE_TX: begin
                    // El byte ya está en byte_to_send, la lógica comb. lo pone
                    // en uart_wdata_o y activa uart_we_o con addr=10.
                    // En el siguiente ciclo trigereamos el send.
                    state <= S_TRIGGER_SEND;
                end

                // =============================================================
                // Sub-rutina de envío: Activar bit send
                // =============================================================
                S_TRIGGER_SEND: begin
                    state <= S_WAIT_SEND_LATCH;
                end

                // =============================================================
                // Sub-rutina de envío: Esperar 1 ciclo para que el flag se vea
                // =============================================================
                S_WAIT_SEND_LATCH: begin
                    state <= S_WAIT_SEND_DONE;
                end

                // =============================================================
                // Sub-rutina de envío: Esperar que la UART termine (send=0)
                // =============================================================
                S_WAIT_SEND_DONE: begin
                    if (uart_rdata_i[0] == 1'b0) begin
                        state <= return_state;  // Volver al estado que pidió el envío
                    end
                    // Si send_pending sigue en 1, esperar aquí
                end

                // =============================================================
                // DONE: Transmisión completa, volver a IDLE
                // =============================================================
                S_DONE: begin
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
