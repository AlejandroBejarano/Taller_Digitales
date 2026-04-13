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
// ROM asíncrona o síncrona de 1 ciclo de latencia (IP Xilinx Block RAM):
//   TX_FETCH fija rom_addr → TX_LOAD ya tiene el dato disponible.
//
// Correcciones respecto a versión anterior:
//   [FIX-1] inc_counter: se activa solo en TX_WAIT cuando rdata[0]=0 Y
//           char_counter < MSG_LEN-1. Evita doble incremento en último char.
//   [FIX-2] tx_done_o: pulso de 1 ciclo (solo en DONE), no nivel sostenido.
//   [FIX-3] RX_CLEAR: wdata=0 limpia new_rx_flag (bit1=0 en uart_interface).
//           Documentado explícitamente.
//   [FIX-4] DONE retorna a IDLE incondicionalmente (sin quedarse colgado).
//   [FIX-5] MSG_LEN parametrizable; char_counter usa $clog2 para tamaño mínimo.
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
        IDLE     = 4'd0,
        TX_FETCH = 4'd1,
        TX_LOAD  = 4'd2,
        TX_START = 4'd3,
        TX_WAIT  = 4'd4,
        TX_DONE  = 4'd5,
        RX_WAIT  = 4'd6,
        RX_READ  = 4'd7,
        RX_CLEAR = 4'd8,
        DONE     = 4'd9
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
    //    Condiciones de transición basadas en current_state y entradas.
    // =========================================================================
    always_comb begin
        next_state = current_state;

        case (current_state)
            IDLE:
                if (start_tx_i)
                    next_state = TX_FETCH;

            TX_FETCH:
                // 1 ciclo de espera: ROM síncrona fija dirección → dato listo en TX_LOAD
                next_state = TX_LOAD;

            TX_LOAD:
                next_state = TX_START;

            TX_START:
                next_state = TX_WAIT;

            TX_WAIT:
                if (rdata_i[0] == 1'b0) begin  // send_pending bajó → TX completó
                    if (char_counter == CNT_W'(MSG_LEN - 1))
                        next_state = TX_DONE;   // <--- AHORA VA A TX_DONE PRIMERO
                    else
                        next_state = TX_FETCH;  // Hay más bytes: siguiente caracter
                end

            TX_DONE:
                next_state = RX_WAIT; // Tras 1 ciclo de pulso, pasamos a esperar respuesta

            RX_WAIT:
                if (rdata_i[1] == 1'b1)         // new_rx_flag subió → byte recibido
                    next_state = RX_READ;

            RX_READ:
                next_state = RX_CLEAR;

            RX_CLEAR:
                next_state = DONE;

            DONE:
                // [FIX-4]: Retorna siempre a IDLE. El control principal captura
                // rx_done_o/tx_done_o en este único ciclo.
                next_state = IDLE;

            default:
                next_state = IDLE;
        endcase
    end

    // =========================================================================
    // 3. Lógica de Salida (Combinacional - Moore estricta)
    //    Las salidas dependen ÚNICAMENTE de current_state.
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
                clr_counter = 1'b1;  // Resetea el contador mientras espera
            end

            TX_FETCH: begin
                // ROM recibe rom_addr_o en este ciclo (ahora calculada secuencialmente).
            end

            TX_LOAD: begin
                // Escribe el byte de la ROM en el registro TX de uart_interface
                we_o    = 1'b1;
                addr_o  = 2'b10;                // Dirección del registro TX
                wdata_o = {24'd0, rom_data_i};  // Byte a transmitir (8 LSB)
            end

            TX_START: begin
                // Levanta bit0 (send) en registro CTRL para disparar la transmisión
                we_o    = 1'b1;
                addr_o  = 2'b00;          // Dirección del registro CTRL
                wdata_o = 32'h0000_0001;  // bit0=1: activa send_pending
            end

            TX_WAIT: begin
                // Lee registro CTRL y monitorea bit0 (send_pending).
                we_o   = 1'b0;
                addr_o = 2'b00;
            end
            
            TX_DONE: begin
                // Genera pulso de 1 ciclo indicando fin de transmisión (para iniciar timeout)
                tx_done_o = 1'b1; 
            end

            RX_WAIT: begin
                // Lee registro CTRL y monitorea bit1 (new_rx_flag).
                we_o   = 1'b0;
                addr_o = 2'b00;
            end

            RX_READ: begin
                // Lee registro RX (addr=2'b11) → captura dato en FF de rx_data_o
                we_o   = 1'b0;
                addr_o = 2'b11;
            end

            RX_CLEAR: begin
                // Limpia new_rx_flag en uart_interface escribiendo 0 en addr=00.
                // [FIX-3]: wdata=0x0000_0000 → bit1=0 → uart_interface ejecuta:
                //   if (!wdata_i[1]) new_rx_flag = 0  (condición de CLEAR del flag).
                we_o    = 1'b1;
                addr_o  = 2'b00;
                wdata_o = 32'h0000_0000;
            end

            DONE: begin
                // El Control Principal captura rx_done_o en este ciclo.
                rx_done_o = 1'b1;
            end

            default: ;
        endcase
    end

    // =========================================================================
    // 4. Datapath Secuencial
    // =========================================================================

    // --- Dirección a la ROM (Secuencial con Reset) ---
    // [NUEVO]: Se convierte en registro para evitar XX en simulación.
    // Se inicializa en 0 y carga base_addr_i al iniciar.
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            rom_addr_o <= 32'd0;
        end else if (current_state == IDLE && start_tx_i) begin
            rom_addr_o <= base_addr_i;
        end else if (inc_counter) begin
            rom_addr_o <= rom_addr_o + 1'b1;
        end
    end

    // --- Control de inc_counter (Combinacional) ---
    // [FIX-1]: Se incrementa SOLO cuando:
    //   - Estamos en TX_WAIT (esperando fin de TX),
    //   - La transmisión terminó (send_pending=0), Y
    //   - No es el último caracter (char_counter < MSG_LEN-1).
    always_comb begin
        inc_counter = (current_state == TX_WAIT)              &&
                      (rdata_i[0] == 1'b0)                    &&
                      (char_counter != CNT_W'(MSG_LEN - 1));
    end

    // --- Contador de caracteres (Secuencial) ---
    always_ff @(posedge clk_i) begin
        if (rst_i || clr_counter)
            char_counter <= '0;
        else if (inc_counter)
            char_counter <= char_counter + 1'b1;
    end

    // --- Captura del dato recibido (Secuencial) ---
    // Se captura rdata_i[7:0] (addr=2'b11, Reg RX) cuando estamos en RX_READ.
    always_ff @(posedge clk_i) begin
        if (rst_i)
            rx_data_o <= 8'd0;
        else if (current_state == RX_READ)
            rx_data_o <= rdata_i[7:0];
    end

endmodule