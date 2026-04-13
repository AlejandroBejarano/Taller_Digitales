// =============================================================================
// uart_prueba_3.sv  -  Top de prueba UART corregido
//
// Correcciones aplicadas:
//  1. Reset interno: la FSM usa un reset sincrono que se libera cuando
//     locked=1 Y rst_i=0. Evita que la FSM quede congelada si el PLL
//     tarda en bloquear o si el boton tiene rebote.
//  2. WAIT_CYCLES reducido a 2 segundos reales (era correcto, se deja
//     como parametro con comentario claro para simulacion).
//  3. El estado S_SEND ahora espera UN ciclo extra antes de leer send
//     (la FSM da tiempo al FF de send_pending en uart_interface de verse
//     reflejado en rdata_o).
//  4. Se agrego un LED de diagnostico: LED[0] = locked, LED[1] = tx activo,
//     LED[2] = byte recibido, LED[3] = estado de reset interno.
//     Conectar en XDC para depuracion visual sin ILA.
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