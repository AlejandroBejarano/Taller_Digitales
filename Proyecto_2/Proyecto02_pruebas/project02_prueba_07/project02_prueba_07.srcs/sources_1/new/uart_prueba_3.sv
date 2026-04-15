// =============================================================================
// uart_prueba_3.sv — Top de prueba UART con eco y LEDs de diagnóstico
//
// Propósito:
//   Módulo de prueba independiente para verificar el canal UART.
//   Al arrancar envía un byte 0x55 y luego entra en modo eco: cualquier
//   byte recibido desde la PC se retransmite inmediatamente de vuelta.
//   Útil para comprobar la cadena completa: PLL → uart_interface → UART.vhd.
//
// Flujo de operación:
//   1. Al salir del reset interno el sistema espera WAIT_CYCLES ciclos.
//   2. Transmite 0x55 (patrón alternante: prueba de todos los bits del TX).
//   3. Entra en S_IDLE esperando new_rx_flag=1 (byte llegando desde PC).
//   4. Lee el byte y lo reenvía por TX (eco).
//   5. Repite desde paso 3 indefinidamente.
//
// FSM (state_t):
//   S_WAIT        – Espera WAIT_CYCLES ciclos de estabilización.
//   S_WRITE_TX    – Escribe 0x55 en registro TX (addr=10).
//   S_SEND        – Activa bit send en CTRL (addr=00, bit0=1).
//   S_SEND_WAIT1  – Espera 1 ciclo para que send_pending aparezca en rdata.
//   S_WAIT_DONE   – Polling: espera send_pending=0 (TX libre).
//   S_IDLE        – Espera new_rx_flag=1 (byte entrante desde PC).
//   S_READ_RX     – Lee byte recibido (addr=11); guarda en rx_byte.
//   S_CLEAR_NEWRX – Escribe CTRL con bit1=0 para limpiar new_rx_flag.
//   S_ECHO_TX     – Carga rx_byte en registro TX para el eco.
//   S_ECHO_SEND   – Activa send para el eco.
//   S_ECHO_WAIT1  – Ciclo de latencia antes de S_WAIT_DONE.
//
// Entradas:
//   clk_100MHz – Reloj de entrada de la Basys3 (100 MHz); convertido a 16 MHz por PLL.
//   rst_i      – BTNC activo alto; resetea el PLL y la FSM.
//   rx         – Línea serie de recepción (pin FPGA).
//
// Salidas:
//   tx         – Línea serie de transmisión (pin FPGA).
//   led[3:0]   – LEDs de diagnóstico:
//                  [0] = locked (PLL bloqueado)
//                  [1] = send_pending (TX activo)
//                  [2] = new_rx_flag (byte recibido esperando lectura)
//                  [3] = rst_internal (reset interno activo)
//
// Variables internas:
//   clk_16MHz   – Reloj de 16 MHz generado por el PLL clk_wiz_0.
//   locked      – Señal del PLL indicando estabilidad del reloj.
//   rst_internal– Reset sincronizado a 16 MHz (rst_i OR ~locked).
//   we/addr/wdata/rdata – Bus estándar hacia uart_interface.
//   counter     – Contador de ciclos para WAIT_CYCLES.
//   rx_byte     – Último byte recibido; copiado desde rdata en S_READ_RX.
//
// Nota:
//   WAIT_CYCLES = 200 para simulación. Cambiar a 16_000_000*2 para síntesis.
// =============================================================================
module uart_prueba_3 (
    input  logic        clk_100MHz,
    input  logic        rst_i,       // BTNC: activo alto
    input  logic        rx,
    output logic        tx,
    output logic [3:0]  led          // LEDs de diagnostico (opcional)
);

    // -------------------------------------------------------------------------
    // PLL: 100 MHz -> 16 MHz
    // -------------------------------------------------------------------------
    logic clk_16MHz;
    logic locked;

    clk_wiz_0 pll_inst (
        .clk_in1  (clk_100MHz),
        .clk_out1 (clk_16MHz),
        .reset    (rst_i),
        .locked   (locked)
    );

    // -------------------------------------------------------------------------
    // Reset interno: activo mientras rst_i=1 O PLL no ha bloqueado.
    // Se sincroniza al dominio de 16 MHz con dos FFs para evitar metaestabilidad.
    // -------------------------------------------------------------------------
    logic rst_meta, rst_sync, rst_internal;

    always_ff @(posedge clk_16MHz) begin
        rst_meta    <= rst_i | ~locked;
        rst_sync    <= rst_meta;
        rst_internal <= rst_sync;
    end

    // -------------------------------------------------------------------------
    // Bus hacia uart_interface
    // -------------------------------------------------------------------------
    logic        we;
    logic [1:0]  addr;
    logic [31:0] wdata;
    logic [31:0] rdata;

    uart_interface uart_if (
        .clk_i   (clk_16MHz),
        .rst_i   (rst_internal),
        .we_i    (we),
        .addr_i  (addr),
        .wdata_i (wdata),
        .rdata_o (rdata),
        .rx      (rx),
        .tx      (tx)
    );

    // -------------------------------------------------------------------------
    // Parametros de tiempo
    // Para SINTESIS:    WAIT_CYCLES = 16_000_000 * 2   (2 segundos)
    // Para SIMULACION:  WAIT_CYCLES = 200              (cambiar aqui)
    // -------------------------------------------------------------------------
    localparam int WAIT_CYCLES = 200;

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        S_WAIT,         // Espera inicial (WAIT_CYCLES ciclos)
        S_WRITE_TX,     // Escribe 0x55 en registro TX  (addr=10)
        S_SEND,         // Activa send                   (addr=00, bit0=1)
        S_SEND_WAIT1,   // Espera 1 ciclo para que send_pending se refleje
        S_WAIT_DONE,    // Espera que send=0 (TX termino)
        S_IDLE,         // Espera new_rx=1
        S_READ_RX,      // Lee byte recibido              (addr=11)
        S_CLEAR_NEWRX,  // Limpia new_rx                  (addr=00, bit1=0)
        S_ECHO_TX,      // Escribe byte eco en registro TX
        S_ECHO_SEND,    // Activa send para eco
        S_ECHO_WAIT1    // Espera 1 ciclo antes de S_WAIT_DONE
    } state_t;

    state_t      state;
    logic [31:0] counter;
    logic [7:0]  rx_byte;

    // -------------------------------------------------------------------------
    // Logica combinacional del bus
    // -------------------------------------------------------------------------
    always_comb begin
        we    = 1'b0;
        addr  = 2'b00;
        wdata = 32'b0;

        unique case (state)
            S_WRITE_TX:   begin we = 1'b1; addr = 2'b10; wdata = 32'h00000055; end
            S_SEND:       begin we = 1'b1; addr = 2'b00; wdata = 32'h00000001; end
            S_SEND_WAIT1: begin we = 1'b0; addr = 2'b00; wdata = 32'b0;        end
            S_WAIT_DONE:  begin we = 1'b0; addr = 2'b00; wdata = 32'b0;        end
            S_IDLE:       begin we = 1'b0; addr = 2'b00; wdata = 32'b0;        end
            S_READ_RX:    begin we = 1'b0; addr = 2'b11; wdata = 32'b0;        end
            // Limpiar new_rx: escribir addr=00 con bit1=0 y bit0=0
            S_CLEAR_NEWRX:begin we = 1'b1; addr = 2'b00; wdata = 32'h00000000; end
            S_ECHO_TX:    begin we = 1'b1; addr = 2'b10; wdata = {24'b0, rx_byte}; end
            S_ECHO_SEND:  begin we = 1'b1; addr = 2'b00; wdata = 32'h00000001; end
            S_ECHO_WAIT1: begin we = 1'b0; addr = 2'b00; wdata = 32'b0;        end
            default:      begin we = 1'b0; addr = 2'b00; wdata = 32'b0;        end
        endcase
    end

    // -------------------------------------------------------------------------
    // Transiciones de estado (sincrono con reset interno)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_16MHz) begin
        if (rst_internal) begin
            state   <= S_WAIT;
            counter <= 32'b0;
            rx_byte <= 8'h00;
        end else begin
            unique case (state)

                S_WAIT: begin
                    if (counter == WAIT_CYCLES - 1) begin
                        counter <= 32'b0;
                        state   <= S_WRITE_TX;
                    end else begin
                        counter <= counter + 1;
                    end
                end

                S_WRITE_TX:    state <= S_SEND;

                // Activa send: en el siguiente ciclo uart_interface
                // ya tiene send_pending=1 y lo refleja en rdata
                S_SEND:        state <= S_SEND_WAIT1;

                // Ciclo de latencia: deja que send_pending aparezca en rdata[0]
                S_SEND_WAIT1:  state <= S_WAIT_DONE;

                // Espera que send_pending baje (TX completo)
                S_WAIT_DONE: begin
                    if (!rdata[0]) state <= S_IDLE;
                end

                // Espera byte entrante
                S_IDLE: begin
                    if (rdata[1]) state <= S_READ_RX;
                end

                S_READ_RX: begin
                    rx_byte <= rdata[7:0];
                    state   <= S_CLEAR_NEWRX;
                end

                S_CLEAR_NEWRX: state <= S_ECHO_TX;

                S_ECHO_TX:     state <= S_ECHO_SEND;

                S_ECHO_SEND:   state <= S_ECHO_WAIT1;

                S_ECHO_WAIT1:  state <= S_WAIT_DONE;

                default: state <= S_WAIT;

            endcase
        end
    end

    // -------------------------------------------------------------------------
    // LEDs de diagnostico
    //  LED[0] = PLL locked
    //  LED[1] = send activo (transmitiendo)
    //  LED[2] = new_rx flag (byte recibido esperando lectura)
    //  LED[3] = reset interno activo
    // -------------------------------------------------------------------------
    assign led[0] = locked;
    assign led[1] = rdata[0];   // send_pending
    assign led[2] = rdata[1];   // new_rx_flag
    assign led[3] = rst_internal;

endmodule