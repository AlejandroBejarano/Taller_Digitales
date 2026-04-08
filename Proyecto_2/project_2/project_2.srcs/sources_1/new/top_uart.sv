module top_uart (
    input  logic       clk,
    input  logic       rst,
    input  logic       rx,
    input  logic       new_question,
    input  logic [7:0] question_selected,
    output logic       tx
);

    // Señales para la comunicación entre módulos
    logic we;
    logic written;
    logic [7:0] w_data;
    logic [7:0] r_data;
    logic new_rx;
    logic new_question;

    // Instancia del controlador UART
    uart_controller controller (
        .clk(clk),
        .rst(rst),
        .new_question(new_question),
        .question_selected(question_selected),
        .we(we),
        .written(written),
        .w_data(w_data)
    );


    // Instancia del módulo UART
    UART uart_inst (
        .clk         (clk),
        .reset       (rst),

        // TRANSMISIÓN
        .tx_start    (we),
        .tx_rdy      (written),
        .data_in     (w_data), // Solo se envía un byte (8 bits)

        // RECEPCIÓN
        .rx_data_rdy (new_rx),
        .data_out    (r_data), // Solo se recibe un byte (8 bits)
        
        // UART
        .rx          (rx),
        .tx          (tx)
    );
endmodule