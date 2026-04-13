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
    //         new_rx_flag) para eliminar race conditions. En el codigo original, el
    //         mismo always_ff escribia ctrl_reg[0] desde tres ramas distintas sin
    //         orden garantizado (case 3'b100, if(tx_rdy), edge-detect), lo que
    //         generaba comportamiento no determinista.
    logic        send_pending;
    logic        new_rx_flag;

    // CAMBIO: next_send_pending y next_new_rx_flag se declaran aqui como logicas
    //         combinacionales (driven por always_comb) en lugar de variables con
    //         asignacion bloqueante (=) dentro de always_ff.
    //         Razon: cuando se usan con (=) dentro de always_ff, Vivado las sintetiza
    //         como flip-flops. Al no tener salidas usadas fuera del mismo bloque
    //         always_ff, el sintetizador las elimina con el warning:
    //           "Unused sequential element next_send_pending_reg was removed"
    //           "Unused sequential element next_new_rx_flag_reg was removed"
    //         Esto destruia la logica de prioridades en sintesis aunque funcionara
    //         correctamente en simulacion behavioral, causando fallos en TEST 5
    //         (segunda ronda) solo en post-synthesis. Al ser always_comb son wires
    //         reales que Vivado nunca puede eliminar.
    logic        next_send_pending;
    logic        next_new_rx_flag;

    // Senales desde/hacia el core UART (byte-oriented)
    logic        uart_rx_rdy;
    logic [7:0]  rx_data;

    // -------------------------------------------------------------------------
    // rdata_o COMBINACIONAL
    // CAMBIO: Se movio rdata_o de always_ff a always_comb para que la FSM
    //         lea el valor actualizado en el mismo ciclo sin latencia adicional.
    //         En el original, estar dentro del FF introducia un ciclo de retardo
    //         que causaba lecturas desactualizadas (stale reads).
    //         ctrl_reg[0] => send_pending, ctrl_reg[1] => new_rx_flag.
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
    // CAMBIO: Este bloque always_comb reemplaza las asignaciones bloqueantes (=)
    //         que antes estaban dentro del always_ff. La logica de prioridades es:
    //
    //         send_pending: tx_rdy baja (prioridad maxima) > escritura bus (SET)
    //         new_rx_flag:  uart_rx_rdy sube (SET, prioridad alta) > bus CLEAR
    //
    //         Al ser always_comb, next_* son wires sintetizables que sobreviven
    //         la sintesis y producen el mismo comportamiento que en simulacion.
    // -------------------------------------------------------------------------
    always_comb begin
        // Valores por defecto: mantener estado actual de los FFs
        next_send_pending = send_pending;
        next_new_rx_flag  = new_rx_flag;

        // Escrituras del bus (prioridad base)
        if (we_i && addr_i == 2'b00) begin
            // CAMBIO: En lugar de escribir directamente en ctrl_reg, se usan
            //         next_* para que la resolucion de prioridades ocurra de
            //         forma controlada, evitando asignaciones que se pisan entre si.
            if ( wdata_i[0]) next_send_pending = 1'b1; // SET send_pending
            if (!wdata_i[1]) next_new_rx_flag  = 1'b0; // CLEAR new_rx_flag
        end

        // CAMBIO: Prioridad SET > CLEAR para new_rx_flag.
        //         En el original, ctrl_reg[1] se escribia desde el case (CLEAR) y
        //         desde if(uart_rx_rdy) (SET) en el mismo always_ff sin orden
        //         garantizado, con riesgo de perder bytes recibidos. Con next_*,
        //         si uart_rx_rdy y el CLEAR ocurren en el mismo ciclo, el SET
        //         tiene prioridad: el byte no se pierde.
        if (uart_rx_rdy)
            next_new_rx_flag = 1'b1;

        // CAMBIO: Prioridad tx_rdy > escritura en send_pending.
        //         En el original, si tx_rdy llegaba en el mismo ciclo en que la
        //         FSM escribia wdata[0]=1, ambas ramas colisionaban sobre ctrl_reg[0].
        //         Con next_*, tx_rdy baja send_pending incondicionalmente (prioridad
        //         maxima) y la escritura solo aplica si TX ya esta libre.
        if (tx_rdy)
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
            if (uart_rx_rdy)
                rx_reg <= rx_data;

            // Registrar los valores de prioridad resuelta (combinacional -> FF)
            send_pending <= next_send_pending;
            new_rx_flag  <= next_new_rx_flag;

            // CAMBIO: Generacion de tx_start simplificada.
            //         Antes se usaban las senales auxiliares 'send' y 'send_prev'
            //         que Vivado tambien eliminaba como FFs inutilizados (warning
            //         "Unused sequential element send_reg was removed"). Ahora se
            //         detecta el flanco de subida comparando send_pending (valor FF
            //         del ciclo anterior) con next_send_pending (wire combinacional
            //         del ciclo actual). Un ciclo, sin FFs extra, sin warnings.
            tx_start <= next_send_pending && !send_pending;
        end
    end

    // Instancia del modulo UART
    UART uart_inst (
        .clk         (clk_i),
        .reset       (rst_i),
        .tx_start    (tx_start),
        .tx_rdy      (tx_rdy),
        // CAMBIO: se pasa tx_reg (8 bits) directamente porque UART es byte-oriented.
        //         Antes se hacia tx_reg[7:0] desde un registro de 32 bits, lo cual
        //         era redundante e innecesariamente amplio.
        .data_in     (tx_reg),
        // CAMBIO: uart_rx_rdy es salida del UART (indica dato listo); rx_data recibe
        //         el byte. Antes, new_rx y rx_reg[7:0] estaban directamente conectados
        //         al modulo UART sin las senales intermedias necesarias para el control
        //         de flags.
        .rx_data_rdy (uart_rx_rdy),
        .data_out    (rx_data),
        .rx          (rx),
        .tx          (tx)
    );

endmodule