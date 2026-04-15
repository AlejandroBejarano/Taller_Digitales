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

    // Señales internas
    logic        tx_rdy;
    logic        tx_start;
    logic [7:0]  tx_reg;
    logic [7:0]  rx_reg;
    logic        send_pending;
    logic        new_rx_flag;
    
    logic        next_send_pending;
    logic        next_new_rx_flag;

    logic        uart_rx_rdy;
    logic [7:0]  rx_data;

    // Prevención de valores indeterminados 'X' durante el reset
    logic tx_rdy_safe;
    logic uart_rx_rdy_safe;
    assign tx_rdy_safe      = rst_i ? 1'b0 : tx_rdy;
    assign uart_rx_rdy_safe = rst_i ? 1'b0 : uart_rx_rdy; 

    // Lectura del bus
    always_comb begin
        case (addr_i)
            2'b00:   rdata_o = {30'b0, new_rx_flag, send_pending};
            2'b11:   rdata_o = {24'b0, rx_reg};
            default: rdata_o = 32'b0;
        endcase
    end

    // Resolución de prioridades (Combinacional)
    always_comb begin
        next_send_pending = send_pending;
        next_new_rx_flag  = new_rx_flag;

        // Escritura del CPU/FSM superior
        if (we_i && addr_i == 2'b00) begin
            if ( wdata_i[0]) next_send_pending = 1'b1;
            if (!wdata_i[1]) next_new_rx_flag  = 1'b0;
        end

        // Eventos del Hardware (Tienen prioridad)
        if (uart_rx_rdy_safe)            next_new_rx_flag = 1'b1;
        if (tx_rdy_safe && send_pending) next_send_pending = 1'b0;
    end

    // Registros secuenciales
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            tx_reg       <= 8'h00;
            rx_reg       <= 8'h00;
            send_pending <= 1'b0;
            new_rx_flag  <= 1'b0;
            tx_start     <= 1'b0;
        end else begin
            if (we_i && addr_i == 2'b10) tx_reg <= wdata_i[7:0];
            if (uart_rx_rdy_safe)        rx_reg <= rx_data;

            send_pending <= next_send_pending;
            new_rx_flag  <= next_new_rx_flag;
            
            // tx_start se mantiene en 1 mientras haya un envío pendiente.
            // Esto soluciona la pérdida de bytes (back-to-back) porque el UART_tx.vhd
            // tiene un delay de IDLE obligatorio y perdía los pulsos de 1 solo ciclo.
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