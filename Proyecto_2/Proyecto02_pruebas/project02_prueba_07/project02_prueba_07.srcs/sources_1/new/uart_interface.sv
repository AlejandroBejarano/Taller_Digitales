// =============================================================================
// uart_interface.sv — Periférico UART con bus de 32 bits tipo memoria
//
// Propósito:
//   Actúa como interfaz de software para el núcleo UART (UART.vhd).
//   El módulo superior (FSM, uart_game_top, etc.) accede a la UART
//   como si fuera un periférico mapeado en memoria, usando un bus de
//   escritura/lectura de 32 bits con 4 direcciones posibles.
//
// Mapa de registros (addr_i):
//   2'b00  (CTRL/STATUS) — lectura:  {30'd0, new_rx_flag, send_pending}
//                        — escritura: bit0=1 activa send_pending;
//                                     bit1=0 limpia new_rx_flag
//   2'b10  (TX_DATA)     — escritura: [7:0] se carga como dato a transmitir
//   2'b11  (RX_DATA)     — lectura:   {24'd0, rx_reg} devuelve el último byte recibido
//
// Señales internas clave:
//   send_pending  – 1 mientras hay un byte en TX_REG pendiente de ser serializado.
//                   Se activa por escritura en CTRL bit0=1 y se limpia cuando
//                   tx_rdy (UART lista) aserta.
//   new_rx_flag   – 1 cuando el UART recibió un nuevo byte; se limpia cuando el
//                   módulo superior escribe CTRL con bit1=0.
//   tx_start      – Se mantiene en 1 mientras send_pending=1 para manejar el
//                   delay de IDLE del UART.vhd sin perder bytes back-to-back.
//   tx_rdy_safe / uart_rx_rdy_safe – versiones con cero forzado durante reset para
//                   evitar valores X en simulación.
//
// Entradas:
//   clk_i    – Reloj del sistema (16 MHz).
//   rst_i    – Reset activo alto (sincrónico al bus).
//   we_i     – Write Enable: 1 indica escritura en este ciclo.
//   addr_i   – Dirección del registro destino/fuente (ver mapa arriba).
//   wdata_i  – Dato a escribir (32 bits).
//   rx       – Línea serial de recepción (conectado al pin FPGA).
//
// Salidas:
//   rdata_o  – Dato leído del registro apuntado por addr_i.
//   tx       – Línea serial de transmisión (conectado al pin FPGA).
// =============================================================================
`timescale 1ns / 1ps

module uart_interface (
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic        we_i,
    input  logic [1:0]  addr_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    input  logic        rx,
    output logic        tx
);

    // -------------------------------------------------------------------------
    // Señales internas
    // -------------------------------------------------------------------------
    logic        tx_rdy;        // Señal del UART.vhd: 1 cuando el TX está libre (listo para nuevo byte)
    logic        tx_start;      // Señal al UART.vhd: 1 para iniciar transmisión de tx_reg
    logic [7:0]  tx_reg;        // Registro de datos a transmitir (cargado desde wdata_i[7:0] en addr=10)
    logic [7:0]  rx_reg;        // Registro del último byte recibido (actualizado cuando uart_rx_rdy sube)
    logic        send_pending;  // 1 = hay transmisión pendiente (activado por sw, limpiado por hw al terminar)
    logic        new_rx_flag;   // 1 = llegó un byte nuevo (activado por hw, limpiado por sw con bit1=0 en CTRL)

    logic        next_send_pending; // Valor combinacional siguiente de send_pending
    logic        next_new_rx_flag;  // Valor combinacional siguiente de new_rx_flag

    logic        uart_rx_rdy;  // Del UART.vhd: 1 cuando hay un byte válido en rx_data
    logic [7:0]  rx_data;      // Del UART.vhd: byte recibido por la línea serial

    // Prevención de valores indeterminados 'X' durante el reset
    // Sin esto, tx_rdy y uart_rx_rdy pueden ser X en sim y causar disparos espurios
    logic tx_rdy_safe;
    logic uart_rx_rdy_safe;
    assign tx_rdy_safe      = rst_i ? 1'b0 : tx_rdy;
    assign uart_rx_rdy_safe = rst_i ? 1'b0 : uart_rx_rdy;

    // -------------------------------------------------------------------------
    // Lectura del bus (combinacional)
    // -------------------------------------------------------------------------
    always_comb begin
        case (addr_i)
            2'b00:   rdata_o = {30'b0, new_rx_flag, send_pending}; // Registro CTRL/STATUS
            2'b11:   rdata_o = {24'b0, rx_reg};                    // Registro RX_DATA
            default: rdata_o = 32'b0;
        endcase
    end

    // -------------------------------------------------------------------------
    // Resolución de prioridades (Combinacional)
    // El hardware (UART core) tiene prioridad sobre las escrituras del software
    // -------------------------------------------------------------------------
    always_comb begin
        next_send_pending = send_pending;
        next_new_rx_flag  = new_rx_flag;

        // Escritura del módulo superior al registro CTRL (addr=00)
        if (we_i && addr_i == 2'b00) begin
            if ( wdata_i[0]) next_send_pending = 1'b1;  // bit0=1: pedir TX
            if (!wdata_i[1]) next_new_rx_flag  = 1'b0;  // bit1=0: limpiar new_rx
        end

        // Eventos del hardware (tienen prioridad sobre SW para evitar race conditions)
        if (uart_rx_rdy_safe)            next_new_rx_flag  = 1'b1; // Nuevo byte llegó
        if (tx_rdy_safe && send_pending) next_send_pending = 1'b0; // TX completó
    end

    // -------------------------------------------------------------------------
    // Registros secuenciales
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            tx_reg       <= 8'h00;
            rx_reg       <= 8'h00;
            send_pending <= 1'b0;
            new_rx_flag  <= 1'b0;
            tx_start     <= 1'b0;
        end else begin
            // Actualizar registro TX cuando SW escribe en addr=10
            if (we_i && addr_i == 2'b10) tx_reg <= wdata_i[7:0];
            // Capturar byte recibido cuando el UART core lo indica
            if (uart_rx_rdy_safe)        rx_reg <= rx_data;

            send_pending <= next_send_pending;
            new_rx_flag  <= next_new_rx_flag;

            // tx_start se mantiene en 1 mientras haya un envío pendiente.
            // El UART.vhd tiene un ciclo de IDLE obligatorio: un pulso de 1 ciclo
            // se perdería; mantenerlo en 1 garantiza que el core lo detecte.
            tx_start <= send_pending;
        end
    end

    // =========================================================
    // INSTANCIA EXACTA DEL VHDL ORIGINAL (DEL ARCHIVO .TXT)
    // =========================================================
    UART uart_core_inst (
        .clk         (clk_i),
        .reset       (rst_i),
        .tx_start    (tx_start),
        .tx_rdy      (tx_rdy),
        .rx_data_rdy (uart_rx_rdy),
        .data_in     (tx_reg),
        .data_out    (rx_data),
        .rx          (rx),
        .tx          (tx)
    );

endmodule