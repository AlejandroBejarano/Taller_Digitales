`timescale 1ns / 1ps
// =============================================================================
// Módulo  : uart_prueba_txyrx
// Función : Top de prueba que instancia uart_system y una Block RAM (IP Vivado)
//           cargada con el archivo .coe de preguntas. Envía las preguntas por
//           UART y captura la respuesta del PC.
//
// Jerarquía:
//   uart_prueba_txyrx
//   ├── uart_system          (wrapper FSM + interface + VHDL UART)
//   │   ├── uart_fsm
//   │   └── uart_interface
//   │       └── UART (VHDL)
//   │           ├── UART_tx (VHDL)
//   │           └── UART_rx (VHDL)
//   └── blk_mem_gen_0        (IP Xilinx Block RAM - Single Port ROM)
//
// Configuración de la IP Block RAM (blk_mem_gen_0):
//   - Memory Type       : Single Port ROM
//   - Port A Width      : 8  (un byte por dirección)
//   - Port A Depth      : 512 (ajustar según cantidad de datos en .coe)
//   - Operating Mode    : Read First
//   - Pipeline Stages   : 1 (Enable Output Register → DOA_REG=1)
//   - Load Init File    : YES → apuntar al .coe de preguntas
//   - Primitive Output  : Block RAM (no distribuida)
//
// Parámetros:
//   MSG_LEN  : Número de bytes por mensaje (= longitud de una fila del .coe)
//              El .coe tiene 32 bytes por pregunta (incluyendo espacios de relleno 0x20)
//   NUM_MSGS : Número de preguntas en el .coe
//   CLK_FREQ : 16 MHz según spec
// =============================================================================
module uart_prueba_txyrx #(
    parameter int MSG_LEN  = 32,   // Bytes por pregunta (ver .coe)
    parameter int NUM_MSGS = 10,   // Número de preguntas en el .coe
    parameter int ADDR_W   = 32   // Ancho del bus de direcciones
) (
    // -------------------------------------------------------------------------
    // Entradas del sistema (conectar a pines físicos de Basys3)
    // -------------------------------------------------------------------------
    input  logic clk_i,         // Reloj de 16 MHz (salida del PLL)
    input  logic rst_i,         // Reset síncrono activo alto (del botón BTNC)

    // Control manual de prueba (botones de la Basys3)
    input  logic btn_send_i,    // Botón para disparar envío de la siguiente pregunta

    // -------------------------------------------------------------------------
    // Pines físicos UART (conector USB-UART de la Basys3 → PC)
    // -------------------------------------------------------------------------
    input  logic rx_i,          // FPGA_RX ← PC_TX  (pin JB o UART nativo)
    output logic tx_o,          // FPGA_TX → PC_RX

    // -------------------------------------------------------------------------
    // LEDs de diagnóstico (opcionales, útiles en prueba sobre hardware)
    // -------------------------------------------------------------------------
    output logic led_tx_done_o, // Parpadea cuando se envió un mensaje completo
    output logic led_rx_done_o, // Parpadea cuando se recibió respuesta
    output logic [7:0] led_rx_data_o // Muestra el byte recibido en LEDs
);

    // =========================================================================
    // Señales internas
    // =========================================================================

    // Interfaz uart_system ↔ ROM
    logic [31:0] rom_addr;
    logic [7:0]  rom_data;

    // Interfaz Control → uart_system
    logic        start_tx;
    logic [31:0] base_addr;
    logic        tx_done;
    logic        rx_done;
    logic [7:0]  rx_data;

    // =========================================================================
    // Lógica de control de prueba
    // Genera pulsos start_tx y calcula base_addr según el índice de pregunta
    // =========================================================================

    // --- Índice de pregunta actual ---
    logic [$clog2(NUM_MSGS)-1:0] msg_idx;

    // --- Detector de flanco del botón (debounce simplificado para simulación) ---
    // En hardware real: agregar debounce. Para prueba en simulación es suficiente.
    logic btn_prev;
    logic btn_pulse;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            btn_prev <= 1'b0;
        end else begin
            btn_prev <= btn_send_i;
        end
    end

    assign btn_pulse = btn_send_i & ~btn_prev; // Flanco positivo

    // --- Máquina de control de prueba ---
    typedef enum logic [1:0] {
        CTRL_IDLE   = 2'd0,
        CTRL_START  = 2'd1,
        CTRL_WAIT   = 2'd2,
        CTRL_NEXT   = 2'd3
    } ctrl_state_t;

    ctrl_state_t ctrl_state;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            ctrl_state <= CTRL_IDLE;
            msg_idx    <= '0;
            start_tx   <= 1'b0;
            base_addr  <= 32'd0;
        end else begin
            start_tx <= 1'b0; // Pulso de 1 ciclo por defecto

            case (ctrl_state)
                CTRL_IDLE: begin
                    // Espera botón para enviar la pregunta actual
                    if (btn_pulse) begin
                        base_addr  <= 32'(msg_idx * MSG_LEN);
                        start_tx   <= 1'b1;
                        ctrl_state <= CTRL_WAIT;
                    end
                end

                CTRL_WAIT: begin
                    // Espera que uart_system termine (tx_done + rx_done)
                    // rx_done indica que se recibió respuesta del PC
                    if (rx_done) begin
                        ctrl_state <= CTRL_NEXT;
                    end
                end

                CTRL_NEXT: begin
                    // Avanza al siguiente mensaje (wraparound)
                    if (msg_idx == $clog2(NUM_MSGS)'(NUM_MSGS - 1))
                        msg_idx <= '0;
                    else
                        msg_idx <= msg_idx + 1'b1;
                    ctrl_state <= CTRL_IDLE;
                end

                default:
                    ctrl_state <= CTRL_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Instancia: uart_system
    // =========================================================================
    uart_system #(
        .MSG_LEN (MSG_LEN)
    ) u_uart_system (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .start_tx_i  (start_tx),
        .base_addr_i (base_addr),
        .tx_done_o   (tx_done),
        .rx_done_o   (rx_done),
        .rx_data_o   (rx_data),
        .rom_addr_o  (rom_addr),
        .rom_data_i  (rom_data),
        .rx          (rx_i),
        .tx          (tx_o)
    );

    // =========================================================================
    // Instancia: Block RAM IP de Vivado (Single Port ROM, 8-bit width)
    //
    // IMPORTANTE: Esta instancia asume que la IP fue generada en Vivado con:
    //   - Nombre del componente : blk_mem_gen_0
    //   - Port A Width          : 8
    //   - Depth                 : al menos NUM_MSGS * MSG_LEN
    //   - Pipeline Stages       : 1 (Output Register habilitado → 2 ciclos latencia)
    //   - COE File              : ruta al archivo .coe con los datos de preguntas
    //
    // Si la IP tiene un nombre distinto, cambiar "blk_mem_gen_0" abajo.
    // La interfaz estándar de blk_mem_gen en modo ROM Single Port es:
    //   clka, addra, douta (no hay wea, dina en modo ROM)
    // =========================================================================
    blk_mem_gen_0 u_rom (
        .clka  (clk_i),
        .addra (rom_addr[8:0]),  // Ajustar ancho según profundidad de la ROM
                                  // 9 bits → 512 posiciones (NUM_MSGS*MSG_LEN ≤ 512)
        .douta (rom_data)
    );

    // =========================================================================
    // Salidas de diagnóstico (LEDs)
    // =========================================================================
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            led_tx_done_o  <= 1'b0;
            led_rx_done_o  <= 1'b0;
            led_rx_data_o  <= 8'h00;
        end else begin
            led_tx_done_o <= tx_done;
            led_rx_done_o <= rx_done;
            if (rx_done)
                led_rx_data_o <= rx_data;
        end
    end

endmodule