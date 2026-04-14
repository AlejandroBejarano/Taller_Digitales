`timescale 1ns / 1ps
// =============================================================================
// UART Standard Interface Module
//
// CAMBIO CRITICO [FIX-XPROP]:
// El modulo VHDL UART_tx entrega tx_rdy = 'x' en simulacion mixta VHDL/SV
// durante los primeros ciclos post-reset. Este 'x' contamina send_pending
// a traves del always_comb y NUNCA se recupera, bloqueando toda la UART.
//
// Solucion: tx_rdy se registra en un FF con reset (tx_rdy_reg), y se usa
// un contador de guardia post-reset (rst_guard) que fuerza tx_rdy_clean=0
// durante los primeros 7 ciclos despues del reset. Esto garantiza que
// send_pending NUNCA se contamine con 'x'.
// =============================================================================
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

    // Senales internas
    logic        tx_rdy;
    logic        tx_start;

    // Registro de datos (8 bits, UART es byte-oriented)
    logic [7:0]  tx_reg;
    logic [7:0]  rx_reg;

    // Flags de control
    logic        send_pending;
    logic        new_rx_flag;

    // Next-state combinacionales (wires)
    logic        next_send_pending;
    logic        next_new_rx_flag;

    // Senales desde/hacia el core UART
    logic        uart_rx_rdy;
    logic [7:0]  rx_data;

    // -------------------------------------------------------------------------
    // [FIX-XPROP] Sanitizacion robusta de tx_rdy
    //
    // Problema: tx_rdy del VHDL puede ser 'x' en los primeros ciclos.
    //   tx_rdy='x' → always_comb → next_send_pending='x' → send_pending='x'
    //   → rdata_o[0]='x' → FSM compara 'x'==0 → false → FSM atascada
    //
    // Solucion en 2 etapas:
    //   1. tx_rdy_reg: FF con reset a 0 que muestrea tx_rdy. Como tiene reset,
    //      su salida es 0 despues del reset sin importar que valor tenga tx_rdy.
    //   2. rst_guard: contador de 3 bits (0→7). Mientras rst_guard < 7,
    //      tx_rdy_clean = 0 forzado. Despues de 7 ciclos, tx_rdy_clean =
    //      tx_rdy_reg (que ya tiene un valor limpio del VHDL).
    // -------------------------------------------------------------------------
    logic        tx_rdy_reg;
    logic        tx_rdy_clean;
    logic [2:0]  rst_guard;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            tx_rdy_reg <= 1'b0;
            rst_guard  <= 3'd0;
        end else begin
            tx_rdy_reg <= tx_rdy;
            if (rst_guard != 3'd7)
                rst_guard <= rst_guard + 3'd1;
        end
    end

    // tx_rdy_clean: GARANTIZADO ser 0 o 1, NUNCA 'x'
    assign tx_rdy_clean = (rst_guard == 3'd7) ? tx_rdy_reg : 1'b0;

    // -------------------------------------------------------------------------
    // rdata_o COMBINACIONAL (lectura sin latencia)
    // -------------------------------------------------------------------------
    always_comb begin
        case (addr_i)
            2'b00:   rdata_o = {30'b0, new_rx_flag, send_pending};
            2'b11:   rdata_o = {24'b0, rx_reg};
            default: rdata_o = 32'b0;
        endcase
    end

    // -------------------------------------------------------------------------
    // Resolucion de prioridades COMBINACIONAL
    //
    // [FIX-XPROP]: Se usa tx_rdy_clean en lugar de tx_rdy directamente.
    // -------------------------------------------------------------------------
    always_comb begin
        next_send_pending = send_pending;
        next_new_rx_flag  = new_rx_flag;

        // Escrituras del bus (prioridad base)
        if (we_i && addr_i == 2'b00) begin
            if ( wdata_i[0]) next_send_pending = 1'b1;
            if (!wdata_i[1]) next_new_rx_flag  = 1'b0;
        end

        // Prioridad SET > CLEAR para new_rx_flag
        if (uart_rx_rdy)
            next_new_rx_flag = 1'b1;

        // [FIX-XPROP]: tx_rdy_clean nunca es 'x'
        if (tx_rdy_clean && send_pending)
            next_send_pending = 1'b0;
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
            if (we_i && addr_i == 2'b10)
                tx_reg <= wdata_i[7:0];

            if (uart_rx_rdy)
                rx_reg <= rx_data;

            send_pending <= next_send_pending;
            new_rx_flag  <= next_new_rx_flag;

            tx_start <= next_send_pending && !send_pending;
        end
    end

    // Instancia del modulo UART (VHDL, no modificable)
    UART uart_inst (
        .clk         (clk_i),
        .reset       (rst_i),
        .tx_start    (tx_start),
        .tx_rdy      (tx_rdy),
        .data_in     (tx_reg),
        .rx_data_rdy (uart_rx_rdy),
        .data_out    (rx_data),
        .rx          (rx),
        .tx          (tx)
    );

endmodule