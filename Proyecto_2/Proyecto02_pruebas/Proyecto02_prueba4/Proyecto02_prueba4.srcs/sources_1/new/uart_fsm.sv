`timescale 1ns / 1ps
// =============================================================================
// Módulo  : uart_fsm
// Función : FSM de Moore que controla la UART para:
//           (1) Transmitir una pregunta completa byte a byte (MSG_LEN chars).
//           (2) Esperar y capturar la respuesta del jugador PC (1 byte: A/B/C/D).
//
// Mapa de registros de uart_interface
//   addr=2'b00  CTRL  : bit0=send_pending (WC),  bit1=new_rx_flag (RW)
//   addr=2'b10  TX    : bits[7:0] = byte a enviar
//   addr=2'b11  RX    : bits[7:0] = byte recibido
//
// ROM síncrona con IP Xilinx Block RAM (DOA_REG=1 → 2 ciclos de latencia):
//   La Block RAM IP de Vivado con DOA_REG=1 tiene un registro de salida
//   adicional, por lo que necesita 2 ciclos desde que la direccion es estable
//   hasta que el dato aparece en douta.
//
//   Secuencia de pipeline para cada byte:
//     TX_ADDR   → rom_addr_o (FF) se estabiliza tras incremento
//     TX_FETCH  → Block RAM registra la direccion (1er ciclo interno)
//     TX_FETCH2 → Block RAM entrega el dato en douta (2do ciclo, DOA_REG=1)
//     TX_LOAD   → FSM lee rom_data_i y lo escribe en TX_REG de uart_interface
//     TX_START  → FSM activa send_pending para disparar transmision
//     TX_WAIT   → FSM espera a que send_pending baje (TX completado)
//
// Correcciones aplicadas:
//   [FIX-1] inc_counter solo en TX_WAIT cuando send_pending=0 y no es ultimo char.
//   [FIX-2] tx_done_o: pulso de 1 ciclo (solo en TX_DONE).
//   [FIX-3] RX_CLEAR: wdata=0 limpia new_rx_flag.
//   [FIX-4] DONE retorna a IDLE incondicionalmente.
//   [FIX-5] MSG_LEN parametrizable; char_counter usa $clog2.
//   [FIX-6] TX_ADDR entre TX_WAIT y TX_FETCH para estabilizar rom_addr_o.
//   [FIX-7] TX_FETCH2 para 2do ciclo de latencia Block RAM DOA_REG=1.
//   [FIX-8] IDLE transita a TX_ADDR (no TX_FETCH) para dar ciclo de
//           estabilizacion al rom_addr_o que se carga con base_addr_i.
// =============================================================================
module uart_fsm #(
    parameter int MSG_LEN = 32  // Número de bytes a transmitir por pregunta
) (
    input  logic        clk_i,
    input  logic        rst_i,

    // -------------------------------------------------------------------------
    // Interfaz con el Control Principal del Juego
    // -------------------------------------------------------------------------
    input  logic        start_tx_i,     // Pulso: iniciar envío de pregunta
    input  logic [31:0] base_addr_i,    // Dirección base de la pregunta en ROM
    output logic        tx_done_o,      // Pulso 1 ciclo: transmisión terminada
    output logic        rx_done_o,      // Pulso 1 ciclo: respuesta recibida
    output logic [7:0]  rx_data_o,      // Byte recibido del jugador PC (A/B/C/D)

    // -------------------------------------------------------------------------
    // Interfaz con la ROM de preguntas (Datapath externo)
    // -------------------------------------------------------------------------
    output logic [31:0] rom_addr_o,     // Dirección hacia la ROM
    input  logic [7:0]  rom_data_i,     // Dato leído de la ROM

    // -------------------------------------------------------------------------
    // Interfaz estándar de 32 bits hacia uart_interface (spec PDF §3.4.3)
    // -------------------------------------------------------------------------
    output logic        we_o,
    output logic [1:0]  addr_o,
    output logic [31:0] wdata_o,
    input  logic [31:0] rdata_i
);

    // =========================================================================
    // Localparams y tipos
    // =========================================================================
    localparam int CNT_W = $clog2(MSG_LEN); // Ancho mínimo del contador

    typedef enum logic [3:0] {
        IDLE      = 4'd0,
        TX_FETCH  = 4'd1,
        TX_LOAD   = 4'd2,
        TX_START  = 4'd3,
        TX_WAIT   = 4'd4,
        TX_DONE   = 4'd5,
        RX_WAIT   = 4'd6,
        RX_READ   = 4'd7,
        RX_CLEAR  = 4'd8,
        DONE      = 4'd9,
        TX_ADDR   = 4'd10, // [FIX-6] Ciclo para estabilizar rom_addr_o
        TX_FETCH2 = 4'd11  // [FIX-7] 2do ciclo latencia Block RAM (DOA_REG=1)
    } state_t;

    state_t current_state, next_state;

    // Datapath interno
    logic [CNT_W-1:0] char_counter;
    logic              inc_counter;
    logic              clr_counter;

    // =========================================================================
    // 1. Registro de Estado (Secuencial)
    // =========================================================================
    always_ff @(posedge clk_i) begin
        if (rst_i)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    // =========================================================================
    // 2. Lógica de Próximo Estado (Combinacional)
    // =========================================================================
    always_comb begin
        next_state = current_state;

        case (current_state)
            IDLE:
                if (start_tx_i)
                    // [FIX-8]: Va a TX_ADDR primero. En IDLE con start_tx_i=1,
                    // el always_ff de rom_addr_o carga base_addr_i. TX_ADDR da
                    // 1 ciclo para que ese FF se estabilice antes de que la
                    // Block RAM lo capture.
                    next_state = TX_ADDR;

            // [FIX-6]: Ciclo de estabilizacion de rom_addr_o.
            // El FF de rom_addr_o actualizo su valor al final del ciclo
            // anterior (IDLE o TX_WAIT). TX_ADDR garantiza que la Block RAM
            // ve la direccion correcta cuando registra en TX_FETCH.
            TX_ADDR:
                next_state = TX_FETCH;

            // Primer ciclo de latencia de la Block RAM.
            // La direccion es estable, la BRAM la registra internamente.
            TX_FETCH:
                // [FIX-7]: Transita a TX_FETCH2 para cubrir el 2do ciclo
                // de latencia (DOA_REG=1 en el Block RAM IP de Vivado).
                next_state = TX_FETCH2;

            // [FIX-7]: Segundo ciclo de latencia de la Block RAM.
            // Al final de este ciclo, douta tiene el dato correcto.
            TX_FETCH2:
                next_state = TX_LOAD;

            TX_LOAD:
                next_state = TX_START;

            TX_START:
                next_state = TX_WAIT;

            TX_WAIT:
                if (rdata_i[0] == 1'b0) begin  // send_pending bajó → TX completó
                    if (char_counter == CNT_W'(MSG_LEN - 1))
                        next_state = TX_DONE;
                    else
                        next_state = TX_ADDR; // [FIX-6]
                end

            TX_DONE:
                next_state = RX_WAIT;

            RX_WAIT:
                if (rdata_i[1] == 1'b1)
                    next_state = RX_READ;

            RX_READ:
                next_state = RX_CLEAR;

            RX_CLEAR:
                next_state = DONE;

            DONE:
                next_state = IDLE; // [FIX-4]

            default:
                next_state = IDLE;
        endcase
    end

    // =========================================================================
    // 3. Lógica de Salida (Combinacional - Moore estricta)
    // =========================================================================
    always_comb begin
        we_o        = 1'b0;
        addr_o      = 2'b00;
        wdata_o     = 32'd0;
        clr_counter = 1'b0;
        tx_done_o   = 1'b0;
        rx_done_o   = 1'b0;

        case (current_state)
            IDLE: begin
                clr_counter = 1'b1;
            end

            TX_ADDR: begin
                // Estado de espera puro - no genera escrituras ni lecturas
            end

            TX_FETCH: begin
                // Block RAM registra la direccion (1er ciclo de latencia)
            end

            TX_FETCH2: begin
                // Block RAM entrega el dato (2do ciclo de latencia, DOA_REG=1)
            end

            TX_LOAD: begin
                we_o    = 1'b1;
                addr_o  = 2'b10;
                wdata_o = {24'd0, rom_data_i};
            end

            TX_START: begin
                we_o    = 1'b1;
                addr_o  = 2'b00;
                wdata_o = 32'h0000_0001;
            end

            TX_WAIT: begin
                we_o   = 1'b0;
                addr_o = 2'b00;
            end

            TX_DONE: begin
                tx_done_o = 1'b1;
            end

            RX_WAIT: begin
                we_o   = 1'b0;
                addr_o = 2'b00;
            end

            RX_READ: begin
                we_o   = 1'b0;
                addr_o = 2'b11;
            end

            RX_CLEAR: begin
                we_o    = 1'b1;
                addr_o  = 2'b00;
                wdata_o = 32'h0000_0000;
            end

            DONE: begin
                rx_done_o = 1'b1;
            end

            default: ;
        endcase
    end

    // =========================================================================
    // 4. Datapath Secuencial
    // =========================================================================

    // --- Dirección a la ROM ---
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            rom_addr_o <= 32'd0;
        end else if (current_state == IDLE && start_tx_i) begin
            rom_addr_o <= base_addr_i;
        end else if (inc_counter) begin
            rom_addr_o <= rom_addr_o + 1'b1;
        end
    end

    // --- Control de inc_counter [FIX-1] ---
    always_comb begin
        inc_counter = (current_state == TX_WAIT)              &&
                      (rdata_i[0] == 1'b0)                    &&
                      (char_counter != CNT_W'(MSG_LEN - 1));
    end

    // --- Contador de caracteres ---
    always_ff @(posedge clk_i) begin
        if (rst_i || clr_counter)
            char_counter <= '0;
        else if (inc_counter)
            char_counter <= char_counter + 1'b1;
    end

    // --- Captura del dato recibido ---
    always_ff @(posedge clk_i) begin
        if (rst_i)
            rx_data_o <= 8'd0;
        else if (current_state == RX_READ)
            rx_data_o <= rdata_i[7:0];
    end

endmodule