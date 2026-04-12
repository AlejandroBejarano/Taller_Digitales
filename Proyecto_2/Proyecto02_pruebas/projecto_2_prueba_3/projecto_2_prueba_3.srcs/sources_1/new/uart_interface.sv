// =============================================================================
// uart_interface.sv - Version corregida (sin race conditions)
//
// Cambios respecto a version con bugs:
//  1. send_pending es un FF dedicado, completamente separado de ctrl_reg.
//     Se setea cuando la FSM escribe addr=00 con wdata[0]=1.
//     Se baja SOLO cuando tx_rdy='1'. Nunca colisiona.
//  2. tx_start es el flanco de subida de send_pending (deteccion correcta).
//  3. new_rx: prioridad al SET sobre el CLEAR en el mismo ciclo.
//  4. ctrl_reg[0] refleja send_pending para que la FSM lo pueda leer
//     via rdata_o sin latencia adicional.
//  5. ctrl_reg[1] refleja new_rx_flag para lectura combinacional.
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

    // -------------------------------------------------------------------------
    // Señales internas
    // -------------------------------------------------------------------------
    logic        tx_rdy;
    logic        tx_start;
    logic [7:0]  tx_data;       // Byte a transmitir
    logic [7:0]  rx_data;       // Byte recibido del modulo UART_rx
    logic        uart_rx_rdy;   // Pulso: nuevo byte disponible del RX

    // FF dedicado para controlar transmision (sin colision con tx_rdy)
    logic        send_pending;
    logic        send_prev;

    // Flag de byte recibido (lectura pendiente por la FSM)
    logic        new_rx_flag;

    // Registros de datos
    logic [7:0]  tx_reg;        // Dato a enviar (addr=10)
    logic [7:0]  rx_reg;        // Ultimo byte recibido (addr=11)

    // -------------------------------------------------------------------------
    // rdata_o COMBINACIONAL - FSM ve valores sin latencia de un ciclo
    // ctrl_reg[0] = send_pending, ctrl_reg[1] = new_rx_flag
    // -------------------------------------------------------------------------
    always_comb begin
        case (addr_i)
            2'b00:   rdata_o = {30'b0, new_rx_flag, send_pending};
            2'b11:   rdata_o = {24'b0, rx_reg};
            default: rdata_o = 32'b0;
        endcase
    end

    // -------------------------------------------------------------------------
    // send_pending: FF dedicado para disparo de transmision
    //
    // Se SETEA cuando la FSM escribe addr=00 con wdata[0]=1.
    // Se BAJA cuando tx_rdy='1' (TX termino).
    // Prioridad: tx_rdy > escritura (evita re-disparos accidentales).
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            send_pending <= 1'b0;
            send_prev    <= 1'b0;
            tx_start     <= 1'b0;
        end else begin
            if (tx_rdy) begin
                // TX termino: bajar send_pending
                send_pending <= 1'b0;
            end else if (we_i && (addr_i == 2'b00) && wdata_i[0] && !send_pending) begin
                // FSM solicita envio y no hay TX en curso
                send_pending <= 1'b1;
            end

            // tx_start: pulso de UN ciclo en el flanco de subida de send_pending
            send_prev <= send_pending;
            tx_start  <= send_pending && !send_prev;
        end
    end

    // -------------------------------------------------------------------------
    // tx_reg: dato a transmitir (addr=10)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            tx_reg <= 8'h00;
        end else if (we_i && (addr_i == 2'b10)) begin
            tx_reg <= wdata_i[7:0];
        end
    end

    // -------------------------------------------------------------------------
    // rx_reg y new_rx_flag
    //
    // new_rx_flag se SETEA cuando llega un byte (uart_rx_rdy).
    // new_rx_flag se BAJA cuando la FSM escribe addr=00 con wdata[1]=0.
    // Prioridad: SET > CLEAR (si en el mismo ciclo llega byte y FSM limpia,
    // el byte no se pierde).
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            rx_reg       <= 8'h00;
            new_rx_flag  <= 1'b0;
        end else begin
            if (uart_rx_rdy) begin
                // Nuevo byte: capturar y setear flag (prioridad alta)
                rx_reg      <= rx_data;
                new_rx_flag <= 1'b1;
            end else if (we_i && (addr_i == 2'b00) && !wdata_i[1]) begin
                // FSM limpia flag (solo si no llego byte en este ciclo)
                new_rx_flag <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Instancia UART (wrapper VHDL con TX y RX)
    // -------------------------------------------------------------------------
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