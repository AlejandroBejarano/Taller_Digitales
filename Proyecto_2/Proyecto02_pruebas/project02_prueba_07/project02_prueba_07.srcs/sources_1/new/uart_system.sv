`timescale 1ns / 1ps

module uart_system (
    input  logic       clk_100MHz,
    input  logic       rst_i,       // Botón Central (Reset)
    input  logic       btn_start_i, // Botón Arriba (Inicia la pregunta)
    input  logic       rx,
    output logic       tx,
    output logic [3:0] led          // LEDs para mostrar la respuesta
);

    // -------------------------------------------------------------------------
    // PLL: 100 MHz -> 16 MHz (Requerido por el VHDL del .txt)
    // -------------------------------------------------------------------------
    logic clk_16MHz;
    logic locked;

    clk_wiz_0 pll_inst (
        .clk_in1  (clk_100MHz),
        .clk_out1 (clk_16MHz),
        .reset    (rst_i),
        .locked   (locked)
    );

    // Reset sincronizado
    logic rst_sys;
    always_ff @(posedge clk_16MHz) begin
        rst_sys <= rst_i | ~locked;
    end

    // -------------------------------------------------------------------------
    // Sincronizador del botón de inicio (Antirrebote básico)
    // -------------------------------------------------------------------------
    logic btn_sync1, btn_sync2, btn_start_pulse;
    always_ff @(posedge clk_16MHz) begin
        if (rst_sys) begin
            btn_sync1 <= 0; btn_sync2 <= 0; btn_start_pulse <= 0;
        end else begin
            btn_sync1 <= btn_start_i;
            btn_sync2 <= btn_sync1;
            btn_start_pulse <= btn_sync1 && !btn_sync2; // Detecta flanco de subida
        end
    end

    // -------------------------------------------------------------------------
    // Instancia de la interfaz UART
    // -------------------------------------------------------------------------
    logic        we;
    logic [1:0]  addr;
    logic [31:0] wdata;
    logic [31:0] rdata;

    uart_interface uart_if (
        .clk_i   (clk_16MHz),
        .rst_i   (rst_sys),
        .we_i    (we),
        .addr_i  (addr),
        .wdata_i (wdata),
        .rdata_o (rdata),
        .rx      (rx),
        .tx      (tx)
    );

    // -------------------------------------------------------------------------
    // ROM DE LA PREGUNTA (Jeopardy)
    // -------------------------------------------------------------------------
    localparam MSG_LEN = 25;
    logic [7:0] question_rom [0:MSG_LEN-1];
    
    initial begin
        // Pregunta: "Capital de CR? A)SJ B)Ca\n"
        question_rom[0]="C"; question_rom[1]="a"; question_rom[2]="p"; question_rom[3]="i";
        question_rom[4]="t"; question_rom[5]="a"; question_rom[6]="l"; question_rom[7]=" ";
        question_rom[8]="C"; question_rom[9]="R"; question_rom[10]="?"; question_rom[11]=" ";
        question_rom[12]="A"; question_rom[13]=")"; question_rom[14]="S"; question_rom[15]="J";
        question_rom[16]=" "; question_rom[17]="B"; question_rom[18]=")"; question_rom[19]="C";
        question_rom[20]="a"; question_rom[21]="\r"; question_rom[22]="\n";
    end

    // -------------------------------------------------------------------------
    // MÁQUINA DE ESTADOS (FSM) PRINCIPAL
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        IDLE,             // Espera que presionen botón
        LOAD_CHAR,        // Carga letra en registro TX (addr 10)
        TRIGGER_SEND,     // Activa bit send (addr 00)
        WAIT_1_CYCLE,     // Espera a que el bit baje al registro
        WAIT_SEND_DONE,   // Espera que send_pending vuelva a 0 (Hardware libre)
        CHECK_NEXT_CHAR,  // Revisa si faltan letras
        WAIT_ANSWER,      // Espera respuesta de Python (new_rx_flag == 1)
        READ_ANSWER       // Lee registro RX (addr 11) y evalúa
    } fsm_state_t;

    fsm_state_t state;
    logic [7:0] char_index;
    logic [7:0] player_answer;

    always_ff @(posedge clk_16MHz) begin
        if (rst_sys) begin
            state      <= IDLE;
            char_index <= 0;
            we         <= 0;
            addr       <= 0;
            wdata      <= 0;
            led        <= 4'b0000;
        end else begin
            we <= 0; // Por defecto no escribir
            
            case (state)
                IDLE: begin
                    char_index <= 0;
                    if (btn_start_pulse) begin
                        state <= LOAD_CHAR;
                        led   <= 4'b0000; // Apagar LEDs al iniciar nueva pregunta
                    end
                end

                // --- FASE DE TRANSMISIÓN DE LA PREGUNTA ---
                LOAD_CHAR: begin
                    we    <= 1'b1; 
                    addr  <= 2'b10;
                    wdata <= {24'd0, question_rom[char_index]};
                    state <= TRIGGER_SEND;
                end

                TRIGGER_SEND: begin
                    we    <= 1'b1; 
                    addr  <= 2'b00;
                    wdata <= 32'h0000_0001; // Activa bit 'send_pending'
                    state <= WAIT_1_CYCLE;
                end

                WAIT_1_CYCLE: begin
                    addr  <= 2'b00; // Preparamos dirección para leer
                    state <= WAIT_SEND_DONE;
                end

                WAIT_SEND_DONE: begin
                    addr <= 2'b00;
                    if (rdata[0] == 1'b0) begin // UART terminó de enviar la letra
                        state <= CHECK_NEXT_CHAR;
                    end
                end

                CHECK_NEXT_CHAR: begin
                    if (char_index == MSG_LEN - 1) begin
                        state <= WAIT_ANSWER; // Ya mandó toda la pregunta, a esperar!
                    end else begin
                        char_index <= char_index + 1;
                        state <= LOAD_CHAR; // Siguiente letra
                    end
                end

                // --- FASE DE RECEPCIÓN DE RESPUESTA ---
                WAIT_ANSWER: begin
                    addr <= 2'b00;
                    if (rdata[1] == 1'b1) begin // ¡Llegó un byte de Python!
                        state <= READ_ANSWER;
                    end
                end

                READ_ANSWER: begin
                    addr <= 2'b11; // Leer el byte recibido
                    player_answer = rdata[7:0];
                    
                    // Limpiar la bandera 'new_rx_flag'
                    we    <= 1'b1; 
                    addr  <= 2'b00; 
                    wdata <= 32'h0000_0000; 
                    
                    // Evaluar la respuesta de Python para el Jeopardy
                    if      (player_answer == 8'h41) led <= 4'b0001; // 'A' -> LED 0
                    else if (player_answer == 8'h42) led <= 4'b0010; // 'B' -> LED 1
                    else if (player_answer == 8'h43) led <= 4'b0100; // 'C' -> LED 2
                    else                             led <= 4'b1000; // Cualquier otra cosa

                    state <= IDLE; // Vuelve a esperar el botón para otra pregunta
                end
            endcase
        end
    end
endmodule