// =============================================================================
// result_sender.sv — Transmisor de resultados y score por UART
//
// Envía secuencias de bytes de resultado al jugador PC según el protocolo:
//   - Resultado de ronda:  [0x05 (ENQ)][correct(0x01) / incorrect(0x00)]
//   - Score update:        [0x06 (ACK)][score_pc][score_fpga]
//   - Fin de partida:      [0x04 (EOT)]
//
// Usa la uart_interface via bus estándar de 32 bits.
// Solo transmite un mensaje a la vez; busy_o indica ocupación.
//
// Entradas:
//   clk_i            – Reloj de sistema (16 MHz).
//   rst_i            – Reset activo alto.
//   send_result_i    – Pulso: iniciar envío de resultado de ronda (ENQ + byte).
//   result_correct_i – Nivel capturado antes del pulso: 1=correcto, 0=incorrecto.
//   send_score_i     – Pulso: iniciar envío de score (ACK + score_pc + score_fpga).
//   score_pc_i       – Puntaje jugador PC  (8 bits, se envía como un byte).
//   score_fpga_i     – Puntaje jugador FPGA (8 bits).
//   send_gameover_i  – Pulso: iniciar envío de fin de partida (EOT).
//   uart_rdata_i     – Lectura del bus UART (para verificar send_pending en ctrl).
//
// Salidas:
//   done_o           – Pulso de 1 ciclo: transmisión completada.
//   busy_o           – Nivel: módulo ocupado (no acepta nuevos comandos).
//   uart_we_o        – Escritura al bus UART.
//   uart_addr_o      – Dirección de registro UART.
//   uart_wdata_o     – Dato a escribir.
//
// FSM (state_t):
//   S_IDLE           – Espera comandos; carga el buffer de bytes a enviar.
//   S_LOAD_BYTE      – Prepara el siguiente byte del buffer.
//   S_WRITE_TX       – Escribe el byte en el registro TX (addr=10).
//   S_TRIGGER_SEND   – Activa el bit send en ctrl (addr=00, wdata[0]=1).
//   S_WAIT_SEND_LATCH– Espera 1 ciclo para que send_pending se propague.
//   S_WAIT_SEND_DONE – Polling de send_pending=0 (UART terminó de transmitir).
//   S_NEXT_BYTE      – Avanza al siguiente byte o va a S_DONE si fue el último.
//   S_DONE           – Un ciclo de done_o=1 antes de volver a S_IDLE.
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
        S_TRIGGER_SEND,      // Activar bit send en registro ctrl
        S_WAIT_SEND_LATCH,   // Esperar 1 ciclo para que send_pending aparezca
        S_WAIT_SEND_DONE,    // Polling: esperar send_pending=0 (UART terminó)
        S_NEXT_BYTE,         // Verificar si hay más bytes en el buffer
        S_DONE               // Señal de finalización (1 ciclo)
    } state_t;

    state_t state;

    // =========================================================================
    // Buffer de bytes a enviar (máximo 4 bytes por secuencia)
    // send_buffer[0..total_bytes-1] contiene la secuencia a transmitir.
    // byte_index apunta al byte actual dentro del buffer.
    // =========================================================================
    logic [7:0]  send_buffer [0:3];
    logic [2:0]  total_bytes;      // Cuántos bytes enviar en esta secuencia
    logic [2:0]  byte_index;       // Índice del byte actual

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
                uart_addr_o  = 2'b10;                          // Registro TX
                uart_wdata_o = {24'b0, send_buffer[byte_index]};
            end
            S_TRIGGER_SEND: begin
                uart_we_o    = 1'b1;
                uart_addr_o  = 2'b00;              // Registro control
                uart_wdata_o = 32'h0000_0001;      // bit 0 = send_pending
            end
            S_WAIT_SEND_LATCH: begin
                uart_addr_o  = 2'b00;  // Leer ctrl para polling (we=0)
            end
            S_WAIT_SEND_DONE: begin
                uart_addr_o  = 2'b00;  // Leer ctrl para verificar send_pending=0
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

                // En IDLE se carga el buffer con la secuencia correcta según
                // el pulso de comando recibido (result, score o gameover).
                S_IDLE: begin
                    byte_index <= 3'd0;

                    if (send_result_i) begin
                        // Secuencia: [ENQ=0x05][resultado: 0x01=OK / 0x00=KO]
                        send_buffer[0] <= ENQ;
                        send_buffer[1] <= result_correct_i ? 8'h01 : 8'h00;
                        total_bytes    <= 3'd2;
                        state          <= S_LOAD_BYTE;

                    end else if (send_score_i) begin
                        // Secuencia: [ACK=0x06][score_pc][score_fpga]
                        send_buffer[0] <= ACK;
                        send_buffer[1] <= score_pc_i;
                        send_buffer[2] <= score_fpga_i;
                        total_bytes    <= 3'd3;
                        state          <= S_LOAD_BYTE;

                    end else if (send_gameover_i) begin
                        // Secuencia: [EOT=0x04]
                        send_buffer[0] <= EOT;
                        total_bytes    <= 3'd1;
                        state          <= S_LOAD_BYTE;
                    end
                end

                S_LOAD_BYTE: begin
                    // Ciclo de preparación antes de escribir (el dato ya está en buffer)
                    state <= S_WRITE_TX;
                end

                S_WRITE_TX: begin
                    // uart_wdata_o ya tiene send_buffer[byte_index] (lógica comb)
                    state <= S_TRIGGER_SEND;
                end

                S_TRIGGER_SEND: begin
                    // Activar send_pending en ctrl reg; UART comenzará a serializar
                    state <= S_WAIT_SEND_LATCH;
                end

                S_WAIT_SEND_LATCH: begin
                    // Dar 1 ciclo para que send_pending se propague al registro de salida
                    state <= S_WAIT_SEND_DONE;
                end

                S_WAIT_SEND_DONE: begin
                    // send_pending (bit 0) vuelve a 0 cuando la UART terminó de transmitir
                    if (uart_rdata_i[0] == 1'b0) begin
                        state <= S_NEXT_BYTE;
                    end
                    // Si sigue en 1, esperar otro ciclo
                end

                S_NEXT_BYTE: begin
                    if (byte_index == total_bytes - 1) begin
                        // Era el último byte: señalizar done
                        state <= S_DONE;
                    end else begin
                        byte_index <= byte_index + 1;
                        state      <= S_LOAD_BYTE;
                    end
                end

                S_DONE: begin
                    // done_o=1 durante este único ciclo; luego vuelve a IDLE
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
