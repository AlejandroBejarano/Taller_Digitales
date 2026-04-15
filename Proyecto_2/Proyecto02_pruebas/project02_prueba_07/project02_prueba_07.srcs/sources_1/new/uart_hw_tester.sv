// =============================================================================
// uart_hw_tester.sv — Top de prueba de lazo completo UART (enviar 'A', recibir 'B')
//
// Propósito:
//   Módulo de prueba mínimo para verificar el canal UART físico en hardware.
//   Al presionar el botón, envía el byte 'A' (0x41) y espera recibir 'B' (0x42)
//   de vuelta. Si lo recibe, enciende led_o.
//   Útil para confirmar que: PLL, uart_interface, UART.vhd y el cable FTDI
//   funcionan correctamente antes de integrar la lógica del juego.
//
// Flujo de operación:
//   1. IDLE: espera btn_edge (flanco de subida del botón, ya sincronizado).
//   2. WRITE_DATA: escribe 0x41 ('A') en registro TX (addr=10).
//   3. TRIGGER_SEND: activa send en CTRL (addr=00, bit0=1).
//   4. WAIT_SEND_DONE: espera send_pending=0 (TX libre).
//   5. WAIT_RX_READY: espera new_rx_flag=1 en CTRL (bit1=1).
//   6. READ_RX_DATA: lee byte recibido (addr=11); si es 'B', enciende led_o.
//   7. CLEANUP: limpia new_rx_flag escribiendo CTRL=0; regresa a IDLE.
//
// FSM (state_t):
//   IDLE           – Espera btn_edge (pulso de 1 ciclo al soltar el botón).
//   WRITE_DATA     – Carga 0x41 en registro TX del uart_interface.
//   TRIGGER_SEND   – Activa bit0 del registro CTRL para iniciar TX.
//   WAIT_SEND_DONE – Polling: rdata[0]==0 cuando TX completó.
//   WAIT_RX_READY  – Polling: rdata[1]==1 cuando llegó un byte.
//   READ_RX_DATA   – Lee rdata[7:0] (byte recibido); decide si encender LED.
//   CLEANUP        – Limpia new_rx_flag (CTRL=0) y vuelve a IDLE.
//
// Entradas:
//   clk_i      – Reloj 100 MHz (pin W5 Basys3); PLL genera 16 MHz interno.
//   rst_i      – BTNC activo alto; resetea PLL y FSM.
//   btn_send_i – Botón Arriba: flanco de subida inicia el envío.
//   rx         – Línea serie de recepción (pin FPGA).
//
// Salidas:
//   tx         – Línea serie de transmisión (pin FPGA).
//   led_o      – Se pone en 1 si la FPGA recibe 'B' (0x42) de vuelta.
//                Sticky: nunca se apaga salvo por reset.
//
// Variables internas:
//   clk_16MHz       – Reloj de 16 MHz generado por clk_wiz_0.
//   locked          – Estabilidad del PLL.
//   rst_sys         – rst_i OR ~locked (asíncrono).
//   btn_sync_1 / btn_send_synced – Doble sincronizador para metaestabilidad.
//   btn_prev / btn_edge – Detector de flanco: btn_edge=1 solo 1 ciclo al subir.
//   we/addr/wdata/rdata – Bus estándar hacia uart_interface.
//   state / next_state  – FSM con lógica separada (ff + comb).
// =============================================================================
`timescale 1ns / 1ps

module uart_hw_tester (
    input  logic clk_i,       // Pin W5 (100 MHz)
    input  logic rst_i,       // Botón Central (Reset)
    input  logic btn_send_i,  // Botón Arriba (Enviar 'A')
    input  logic rx,
    output logic tx,
    output logic led_o        // LED que se encenderá con la 'B'
);

    // Señales de reloj interno y reset unificado
    logic clk_16MHz;
    logic locked; 
    logic rst_sys; 

    assign rst_sys = rst_i | !locked; 

    // 1. Instancia del Clocking Wizard (IP de Vivado)
    clk_wiz_0 clk_gen (
        .clk_in1  (clk_i),     
        .clk_out1 (clk_16MHz), 
        .reset    (rst_i),     
        .locked   (locked)     
    );

    // Señales del bus estándar hacia la UART
    logic        we;
    logic [1:0]  addr;
    logic [31:0] wdata;
    logic [31:0] rdata;

    // 2. Instancia del periférico UART
    uart_interface uut_uart (
        .clk_i   (clk_16MHz), 
        .rst_i   (rst_sys), 
        .we_i    (we),
        .addr_i  (addr),
        .wdata_i (wdata),
        .rdata_o (rdata),
        .rx      (rx),
        .tx      (tx)
    );

    // 3. Sincronizador de botón para evitar metaestabilidad
    logic btn_sync_1, btn_send_synced;
    always_ff @(posedge clk_16MHz) begin
        if (rst_sys) begin
            btn_sync_1      <= 1'b0;
            btn_send_synced <= 1'b0;
        end else begin
            btn_sync_1      <= btn_send_i;
            btn_send_synced <= btn_sync_1;
        end
    end

    // --- CORRECCIÓN 1: Detector de flanco del botón (pulso de 1 ciclo) ---
    // Evita que la FSM cicle múltiples veces por una sola pulsación
    logic btn_prev;
    logic btn_edge;

    always_ff @(posedge clk_16MHz) begin
        if (rst_sys) btn_prev <= 1'b0;
        else         btn_prev <= btn_send_synced;
    end

    assign btn_edge = btn_send_synced & ~btn_prev;

    // 4. Máquina de estados
    typedef enum logic [2:0] {
        IDLE, 
        WRITE_DATA, 
        TRIGGER_SEND, 
        WAIT_SEND_DONE, 
        WAIT_RX_READY,
        READ_RX_DATA,
        CLEANUP
    } state_t;

    state_t state, next_state;

    always_ff @(posedge clk_16MHz) begin
        if (rst_sys) begin
            state <= IDLE;
            led_o <= 1'b0;
        end else begin
            state <= next_state;
            
            // --- CORRECCIÓN 2: LED "sticky" - solo se enciende, nunca se apaga por dato incorrecto ---
            // Así, aunque la FSM ciclara más de una vez, el LED no se apagaría.
            if (state == READ_RX_DATA) begin
                if (rdata[7:0] == 8'h42) 
                    led_o <= 1'b1;
                // Se eliminó el else que apagaba el LED
            end
        end
    end

    always_comb begin
        next_state = state;
        we         = 1'b0;
        addr       = 2'b00;
        wdata      = 32'd0;

        case (state)
            // --- CORRECCIÓN 3: Usar btn_edge en vez de btn_send_synced ---
            IDLE: begin
                if (btn_edge) next_state = WRITE_DATA;
            end

            // Paso 1: Cargar la 'A' en el registro de transmisión (addr=10)
            WRITE_DATA: begin
                we    = 1'b1;
                addr  = 2'b10;
                wdata = {24'd0, 8'h41}; // ASCII 'A'
                next_state = TRIGGER_SEND;
            end

            // Paso 2: Activar el bit 'send' en el registro de control (addr=00)
            TRIGGER_SEND: begin
                we    = 1'b1;
                addr  = 2'b00;
                wdata = 32'h0000_0001; // bit 0 = 1
                next_state = WAIT_SEND_DONE;
            end

            // Paso 3: Esperar a que la UART termine de enviar (bit send vuelve a 0)
            WAIT_SEND_DONE: begin
                addr = 2'b00;
                if (rdata[0] == 1'b0) next_state = WAIT_RX_READY;
            end

            // Paso 4: Esperar a que llegue la respuesta desde Python (bit new_rx == 1)
            WAIT_RX_READY: begin
                addr = 2'b00;
                if (rdata[1] == 1'b1) next_state = READ_RX_DATA;
            end

            // Paso 5: Leer el dato recibido en el registro RX (addr=11)
            READ_RX_DATA: begin
                addr = 2'b11;
                next_state = CLEANUP;
            end

            // --- CORRECCIÓN 4: CLEANUP va directo a IDLE ---
            // Ya no esperamos a soltar el botón aquí porque btn_edge
            // garantiza una sola ejecución por pulsación.
            CLEANUP: begin
                we    = 1'b1;
                addr  = 2'b00;
                wdata = 32'h0000_0000; // Limpia la bandera new_rx
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
endmodule