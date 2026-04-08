// UART Standard Interface Module
// 
// Entradas:
// clk_i: reloj del sistema
// rst_i: reset síncrono
// we_i: write enable, indica si se va a escribir (1) o leer (0) algun registro
// addr_i: dirección del registro (2 bits)
// wdata_i: datos a escribir en el registro (32 bits)
//
// Salidas:
// rdata_o: datos leídos del registro (32 bits)
//
module uart_interface (
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic        we_i,           // we = 1 => write wdata_i en addr_i && we = 0 => read rdata_o de addr_i
    input  logic [1:0]  addr_i,         // Register address
    input  logic [31:0] wdata_i,        // Write data
    output logic [31:0] rdata_o,         // Read data
    input  logic        rx,             // Línea de recepción UART
    output logic        tx              // Línea de transmisión UART
);
    // Señales internas
    logic        tx_rdy;        // Señal que indica la finalización de la transmisión
    logic        tx_start;      // Señal para iniciar la transmisión one shot

    // Registro de datos
    logic [31:0] tx_reg;        // Registro para almacenar el byte a transmitir
    logic [31:0] rx_reg;        // Registro para almacenar el byte recibido

    // Registro de control
    logic new_rx, send, send_prev;   
    logic [31:0] ctrl_reg;       // bit 1: new_rx, bit 0: send

    logic [2:0]  case_addr;
    assign case_addr = {we_i, addr_i}; // Concatenar we_i y addr_i para simplificar el case statement



    always_ff @( posedge clk_i ) begin
        if (rst_i) begin
            rdata_o <= 32'b0;
            tx_reg <= 32'b0;
            rx_reg <= 32'b0;
            send_prev <= 0;
            ctrl_reg <= 32'b0;

        end else begin
        
            case(case_addr)
                // ========= LECTURA ===========
                // Leer estado del uart: new_rx (bit 1) y send (bit 0)
                3'b000: rdata_o <= ctrl_reg; // we = 0, addr = 2'b00, rdata[1] = new_rx, rdata[0] = send

                // Leer el byte recibido en el registro rx
                3'b011: rdata_o <= rx_reg; // we = 0, addr = 2'b11, rdata[7:0] = byte recibido

                // ========= ESCRITURA ============
                // Iniciar transmisión o limpiar new_rx
                3'b100: begin
                    if (wdata_i[0]) ctrl_reg[0] <= 1; // Iniciar transmisión
                    if (!wdata_i[1]) ctrl_reg[1] <= 0; // Limpiar new_rx luego de leer el byte recibido
                end

                // Escribir en el registro tx el byte a transmitir
                3'b110: tx_reg <= wdata_i; // we = 1, addr = 2'b10, wdata[7:0] = byte a transmitir

                default: ;
            endcase
            
            if (new_rx) ctrl_reg[1] <= 1; // flag de recepción de nuevo byte

            // send detection logic
            send <= ctrl_reg[0]; 
            tx_start <= send && !send_prev; // Generar pulso de inicio de transmisión
            if (tx_rdy) begin
                ctrl_reg[0] <= 0; // Clear send when transmission is ready
            end
            send_prev <= send;
        end
    end



    
    // Instancia del módulo UART
    UART uart_inst (
        .clk         (clk_i),
        .reset       (rst_i),
        // TRANSMISIÓN
        .tx_start    (tx_start),
        .tx_rdy      (tx_rdy),
        .data_in     (tx_reg[7:0]), // Solo se envía un byte (8 bits)
        // RECEPCIÓN
        .rx_data_rdy (new_rx),
        .data_out    (rx_reg[7:0]), // Solo se recibe un byte (8 bits)
        // UART
        .rx          (rx),
        .tx          (tx)
    );

endmodule