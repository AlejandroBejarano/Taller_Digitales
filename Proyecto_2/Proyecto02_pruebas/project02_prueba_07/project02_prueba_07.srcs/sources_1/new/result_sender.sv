// =============================================================================
// result_sender.sv — Transmisor de resultados y score por UART
//
// Envía secuencias de bytes de resultado al jugador PC:
//   - Resultado de ronda:  [0x05][correct(1)/incorrect(0)]
//   - Score update:        [0x06][score_pc][score_fpga]
//   - Fin de partida:      [0x04]
//
// Interfaz con uart_interface via bus estándar de 32 bits.
// =============================================================================
`timescale 1ns / 1ps

module result_sender (
    input  logic        clk_i,
    input  logic        rst_i,

    // Control - enviar resultado de ronda
    input  logic        send_result_i,     // Pulso: enviar resultado
    input  logic        result_correct_i,  // 1=correcto, 0=incorrecto

    // Control - enviar actualización de score
    input  logic        send_score_i,      // Pulso: enviar score
    input  logic [7:0]  score_pc_i,        // Puntaje del jugador PC
    input  logic [7:0]  score_fpga_i,      // Puntaje del jugador FPGA

    // Control - enviar fin de partida
    input  logic        send_gameover_i,   // Pulso: enviar game over

    // Estado
    output logic        done_o,            // Pulso: transmisión completada
    output logic        busy_o,            // 1 mientras transmite

    // Bus hacia uart_interface
    output logic        uart_we_o,
    output logic [1:0]  uart_addr_o,
    output logic [31:0] uart_wdata_o,
    input  logic [31:0] uart_rdata_i
);

    // =========================================================================
    // Constantes de protocolo
    // =========================================================================
    localparam [7:0] EOT = 8'h04;  // End of Transmission (fin de partida)
    localparam [7:0] ENQ = 8'h05;  // Enquiry (resultado de ronda)
    localparam [7:0] ACK = 8'h06;  // Acknowledge (score update)

    // =========================================================================
    // FSM States
    // =========================================================================
    typedef enum logic [3:0] {
        S_IDLE,
        S_LOAD_BYTE,         // Preparar byte a enviar
        S_WRITE_TX,          // Escribir byte en registro TX
        S_TRIGGER_SEND,      // Activar bit send
        S_WAIT_SEND_LATCH,   // Esperar 1 ciclo
        S_WAIT_SEND_DONE,    // Esperar que send_pending=0
        S_NEXT_BYTE,         // Verificar si hay más bytes
        S_DONE
    } state_t;

    state_t state;

    // =========================================================================
    // Buffer de bytes a enviar (máximo 4 bytes por secuencia)
    // =========================================================================
    logic [7:0]  send_buffer [0:3];
    logic [2:0]  total_bytes;      // Cuántos bytes enviar en esta secuencia
    logic [2:0]  byte_index;       // Índice del byte actual

    // =========================================================================
    // Salidas del bus UART (combinacionales)
    // =========================================================================
    always_comb begin
        uart_we_o    = 1'b0;
        uart_addr_o  = 2'b00;
        uart_wdata_o = 32'b0;

        case (state)
            S_WRITE_TX: begin
                uart_we_o    = 1'b1;
                uart_addr_o  = 2'b10;
                uart_wdata_o = {24'b0, send_buffer[byte_index]};
            end
            S_TRIGGER_SEND: begin
                uart_we_o    = 1'b1;
                uart_addr_o  = 2'b00;
                uart_wdata_o = 32'h0000_0001;
            end
            S_WAIT_SEND_LATCH: begin
                uart_addr_o  = 2'b00;
            end
            S_WAIT_SEND_DONE: begin
                uart_addr_o  = 2'b00;
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
            state       <= S_IDLE;
            total_bytes <= 3'd0;
            byte_index  <= 3'd0;
            send_buffer[0] <= 8'h00;
            send_buffer[1] <= 8'h00;
            send_buffer[2] <= 8'h00;
            send_buffer[3] <= 8'h00;
        end else begin
            case (state)

                S_IDLE: begin
                    byte_index <= 3'd0;

                    if (send_result_i) begin
                        // Secuencia: [0x05][resultado]
                        send_buffer[0] <= ENQ;
                        send_buffer[1] <= result_correct_i ? 8'h01 : 8'h00;
                        total_bytes    <= 3'd2;
                        state          <= S_LOAD_BYTE;

                    end else if (send_score_i) begin
                        // Secuencia: [0x06][score_pc][score_fpga]
                        send_buffer[0] <= ACK;
                        send_buffer[1] <= score_pc_i;
                        send_buffer[2] <= score_fpga_i;
                        total_bytes    <= 3'd3;
                        state          <= S_LOAD_BYTE;

                    end else if (send_gameover_i) begin
                        // Secuencia: [0x04]
                        send_buffer[0] <= EOT;
                        total_bytes    <= 3'd1;
                        state          <= S_LOAD_BYTE;
                    end
                end

                S_LOAD_BYTE: begin
                    state <= S_WRITE_TX;
                end

                S_WRITE_TX: begin
                    state <= S_TRIGGER_SEND;
                end

                S_TRIGGER_SEND: begin
                    state <= S_WAIT_SEND_LATCH;
                end

                S_WAIT_SEND_LATCH: begin
                    state <= S_WAIT_SEND_DONE;
                end

                S_WAIT_SEND_DONE: begin
                    if (uart_rdata_i[0] == 1'b0) begin
                        state <= S_NEXT_BYTE;
                    end
                end

                S_NEXT_BYTE: begin
                    if (byte_index == total_bytes - 1) begin
                        state <= S_DONE;
                    end else begin
                        byte_index <= byte_index + 1;
                        state      <= S_LOAD_BYTE;
                    end
                end

                S_DONE: begin
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
