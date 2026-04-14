`timescale 1ns / 1ps
// UART Standard Interface Module
//
// Entradas:
// clk_i: reloj del sistema
// rst_i: reset sincrono
// we_i: write enable, indica si se va a escribir (1) o leer (0) algun registro
// addr_i: direccion del registro (2 bits)
// wdata_i: datos a escribir en el registro (32 bits) 
//
// Salidas:
// rdata_o: datos leidos del registro (32 bits)
//
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

    // Registro de datos
    // CAMBIO: Se cambio tx_reg y rx_reg de 32 a 8 bits porque el modulo UART
    //         es byte-oriented; solo consume data_in[7:0] y produce data_out[7:0].
    //         Mantenerlos en 32 bits no tenia sentido funcional y generaba riesgo
    //         de uso accidental de los bits [31:8].
    logic [7:0]  tx_reg;
    logic [7:0]  rx_reg;

    // Registro de control
    // CAMBIO: ctrl_reg[31:0] fue reemplazado por flags explicitos (send_pending y
    //         new_rx_flag) para eliminar race conditions.
    logic        send_pending;
    logic        new_rx_flag;

    // CAMBIO: next_send_pending y next_new_rx_flag se declaran aqui como logicas
    //         combinacionales (driven por always_comb)
    logic        next_send_pending;
    logic        next_new_rx_flag;

    // Senales desde/hacia el core UART (byte-oriented)
    logic        uart_rx_rdy;
    logic [7:0]  rx_data;

    // =========================================================================
    // CORRECCIÓN APLICADA: Señales "safe" para evitar propagación de 'X'
    // =========================================================================
    // tx_rdy_safe fuerza '0' durante reset, eliminando el 'x' en TX.
    // uart_rx_rdy_safe hace lo mismo para RX, evitando que la FSM colapse.
    logic        tx_rdy_safe;
    logic        uart_rx_rdy_safe;
    
    assign tx_rdy_safe      = rst_i ? 1'b0 : tx_rdy;
    assign uart_rx_rdy_safe = rst_i ? 1'b0 : uart_rx_rdy; 
    // =========================================================================

    // -------------------------------------------------------------------------
    // rdata_o COMBINACIONAL
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
    // -------------------------------------------------------------------------
    always_comb begin
        // Valores por defecto: mantener estado actual de los FFs
        next_send_pending = send_pending;
        next_new_rx_flag  = new_rx_flag;

        // Escrituras del bus (prioridad base)
        if (we_i && addr_i == 2'b00) begin
            if ( wdata_i[0]) next_send_pending = 1'b1; // SET send_pending
            if (!wdata_i[1]) next_new_rx_flag  = 1'b0; // CLEAR new_rx_flag
        end

        // Prioridad SET > CLEAR para new_rx_flag.
        // SE USA LA SEÑAL SEGURA: uart_rx_rdy_safe en lugar de uart_rx_rdy
        if (uart_rx_rdy_safe)
            next_new_rx_flag = 1'b1;

        // Prioridad CLEAR send_pending
        if (tx_rdy_safe && send_pending)
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
            // Escribir byte TX cuando la FSM accede a addr=10
            if (we_i && addr_i == 2'b10)
                tx_reg <= wdata_i[7:0];
                
            // Capturar byte recibido del modulo UART
            // SE USA LA SEÑAL SEGURA: uart_rx_rdy_safe en lugar de uart_rx_rdy
            if (uart_rx_rdy_safe)
                rx_reg <= rx_data;

            // Registrar los valores de prioridad resuelta (combinacional -> FF)
            send_pending <= next_send_pending;
            new_rx_flag  <= next_new_rx_flag;

            // Generacion de tx_start
            tx_start <= next_send_pending && !send_pending;
        end
    end

    // DEBUG TEMPORAL: trazar señales criticas de TX
    always_ff @(posedge clk_i) begin
        if (!rst_i) begin
            if (we_i && addr_i == 2'b00 && wdata_i[0])
                $display("[UART_IF %0t] CTRL_WRITE: wdata[0]=1 -> next_sp=%0b sp=%0b tx_start_next=%0b",
                    $time, next_send_pending, send_pending, next_send_pending && !send_pending);
            if (tx_start)
                $display("[UART_IF %0t] TX_START pulsed! tx_reg=0x%02h tx_rdy=%0b sp=%0b",
                    $time, tx_reg, tx_rdy, send_pending);
            if (tx_rdy)
                $display("[UART_IF %0t] TX_RDY received! sp=%0b -> clr=%0b",
                    $time, send_pending, tx_rdy && send_pending);
        end
    end

    // Instancia del modulo UART
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