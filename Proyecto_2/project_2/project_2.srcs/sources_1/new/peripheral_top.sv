module peripheral_top(
    input  logic        clk,
    input  logic        rst,

    // UART physical
    input  logic        rx,
    output logic        tx,

    // Control
    input  logic        start_question,      // pulse to start send/display of selected question
    input  logic [3:0]  question_num,        // 0..9

    // 7-seg inputs (forwarded)
    input  logic [5:0]  timer_i,
    input  logic [3:0]  score_fpga_i,
    input  logic [3:0]  score_pc_i,

    // LCD physical
    output logic        lcd_rs,
    output logic        lcd_rw,
    output logic        lcd_e,
    output logic [7:0]  lcd_d,

    // 7-seg outputs
    output logic [6:0]  seg_o,
    output logic [3:0]  an_o,
    output logic        dp_o,

    // buzzer
    output logic        buzzer
);

    // ------------------------------------------------------------------
    // Local buses for UART and LCD memory-mapped interfaces
    // ------------------------------------------------------------------
    // UART memory-mapped interface (to uart_interface)
    logic        uart_we;
    logic [1:0]  uart_addr;
    logic [31:0] uart_wdata;
    logic [31:0] uart_rdata;

    // LCD memory-mapped interface (to lcd_peripheral)
    logic        lcd_we;
    logic [1:0]  lcd_addr;
    logic [31:0] lcd_wdata;
    logic [31:0] lcd_rdata;

    // ROM query ports from lcd_peripheral
    logic [4:0]  rom_off;
    logic [7:0]  rom_qbyte;
    logic [7:0]  rom_obyte;

    // ------------------------------------------------------------------
    // Instantiate uart_interface
    // ------------------------------------------------------------------
    uart_interface u_uart (
        .clk_i  (clk),
        .rst_i  (rst),
        .we_i   (uart_we),
        .addr_i (uart_addr),
        .wdata_i(uart_wdata),
        .rdata_o(uart_rdata),
        .rx     (rx),
        .tx     (tx)
    );

    // ------------------------------------------------------------------
    // Instantiate lcd_peripheral (includes ROMs)
    // ------------------------------------------------------------------
    lcd_peripheral u_lcd (
        .clk_i          (clk),
        .rst_i          (rst),
        .write_enable_i (lcd_we),
        .addr_i         (lcd_addr),
        .wdata_i        (lcd_wdata),
        .rdata_o        (lcd_rdata),
        .lcd_rs         (lcd_rs),
        .lcd_rw         (lcd_rw),
        .lcd_e          (lcd_e),
        .lcd_d          (lcd_d),
        .question_num   (question_num),
        .question_off   (rom_off),
        .question_byte_o(rom_qbyte),
        .option_byte_o  (rom_obyte)
    );

    // ------------------------------------------------------------------
    // Instantiate segments and buzzer (simple forwarding)
    // ------------------------------------------------------------------
    segments u_seg (
        .clk_i        (clk),
        .rst_i        (rst),
        .timer_i      (timer_i),
        .score_fpga_i (score_fpga_i),
        .score_pc_i   (score_pc_i),
        .seg_o        (seg_o),
        .an_o         (an_o),
        .dp_o         (dp_o)
    );

    // Buzzer instance: buzzer plays when play_ok or play_error are asserted.
    // For now, leave both signals tied low; FSMs may drive them later.
    logic play_ok, play_error;
    assign play_ok = 1'b0;
    assign play_error = 1'b0;

    buzzer u_buzzer (
        .clk        (clk),
        .rst        (rst),
        .play_ok    (play_ok),
        .play_error (play_error),
        .buzzer     (buzzer)
    );

    // ------------------------------------------------------------------
    // UART FSM: send question bytes over UART (one byte at a time)
    // Sequence: IDLE -> LOAD_BYTE -> WRITE_TX_REG -> PULSE_SEND -> WAIT_SENT -> NEXT_BYTE -> DONE
    // ------------------------------------------------------------------
    typedef enum logic [2:0] {U_IDLE, U_LOAD_BYTE, U_WRITE_TX, U_PULSE_SEND, U_WAIT_SENT, U_NEXT_BYTE, U_DONE} uart_state_t;
    uart_state_t u_state;

    logic [5:0] u_byte_idx; // 0..31

    // control handshake timers
    logic start_q_prev;

    always_ff @(posedge clk) begin
        if (rst) begin
            u_state <= U_IDLE;
            u_byte_idx <= 6'd0;
            uart_we <= 1'b0;
            uart_addr <= 2'b00;
            uart_wdata <= 32'd0;
            start_q_prev <= 1'b0;
        end else begin
            // default deassert
            uart_we <= 1'b0;

            case (u_state)
                U_IDLE: begin
                    if (start_question && !start_q_prev) begin
                        u_byte_idx <= 6'd0;
                        u_state <= U_LOAD_BYTE;
                    end
                end

                U_LOAD_BYTE: begin
                    // set ROM offset to read character
                    rom_off <= u_byte_idx[4:0];
                    u_state <= U_WRITE_TX;
                end

                U_WRITE_TX: begin
                    // write byte into UART tx_reg at addr 2'b10
                    uart_addr <= 2'b10; // tx register
                    uart_wdata <= {24'd0, rom_qbyte};
                    uart_we <= 1'b1;
                    u_state <= U_PULSE_SEND;
                end

                U_PULSE_SEND: begin
                    // pulse send bit in ctrl register (addr 2'b00, bit0)
                    uart_addr <= 2'b00;
                    uart_wdata <= 32'd1; // bit0 = 1 -> initiate send
                    uart_we <= 1'b1;
                    u_state <= U_WAIT_SENT;
                end

                U_WAIT_SENT: begin
                    // poll uart_rdata[0] (send) until cleared by uart when tx_rdy
                    if (uart_rdata[0] == 1'b0) begin
                        u_state <= U_NEXT_BYTE;
                    end
                end

                U_NEXT_BYTE: begin
                    if (u_byte_idx == 6'd31) begin
                        u_state <= U_DONE;
                    end else begin
                        u_byte_idx <= u_byte_idx + 6'd1;
                        u_state <= U_LOAD_BYTE;
                    end
                end

                U_DONE: begin
                    // remain done until next start
                    if (!start_question) begin
                        u_state <= U_IDLE;
                    end
                end

                default: u_state <= U_IDLE;
            endcase

            start_q_prev <= start_question;
        end
    end

    // ------------------------------------------------------------------
    // LCD FSM: display question on two lines (first 16 bytes -> line1, next 16 -> line2)
    // Sequence: IDLE -> LOAD_CHAR -> WRITE_DATA -> PULSE_START -> WAIT_DONE -> NEXT_CHAR -> DONE
    // ------------------------------------------------------------------
    typedef enum logic [2:0] {L_IDLE, L_LOAD_CHAR, L_WRITE_DATA, L_PULSE_START, L_WAIT_DONE, L_NEXT_CHAR, L_DONE} lcd_state_t;
    lcd_state_t l_state;

    logic [5:0] l_char_idx; // 0..31

    always_ff @(posedge clk) begin
        if (rst) begin
            l_state <= L_IDLE;
            l_char_idx <= 6'd0;
            lcd_we <= 1'b0;
            lcd_addr <= 2'b00;
            lcd_wdata <= 32'd0;
        end else begin
            // default deassert
            lcd_we <= 1'b0;

            case (l_state)
                L_IDLE: begin
                    if (start_question && !start_q_prev) begin
                        l_char_idx <= 6'd0;
                        l_state <= L_LOAD_CHAR;
                    end
                end

                L_LOAD_CHAR: begin
                    rom_off <= l_char_idx[4:0];
                    l_state <= L_WRITE_DATA;
                end

                L_WRITE_DATA: begin
                    // write data into REG1 (addr 2'b01)
                    lcd_addr <= 2'b01;
                    lcd_wdata <= {24'd0, rom_qbyte};
                    lcd_we <= 1'b1;
                    l_state <= L_PULSE_START;
                end

                L_PULSE_START: begin
                    // issue start pulse with rs = 1 (data)
                    lcd_addr <= 2'b00;
                    // bit0 = pulse_start, bit1 = reg_rs
                    lcd_wdata <= 32'd3; // 0b11 -> start + rs
                    lcd_we <= 1'b1;
                    l_state <= L_WAIT_DONE;
                end

                L_WAIT_DONE: begin
                    // poll lcd_rdata bit 9 (done flag)
                    if (lcd_rdata[9]) begin
                        l_state <= L_NEXT_CHAR;
                    end
                end

                L_NEXT_CHAR: begin
                    if (l_char_idx == 6'd31) begin
                        l_state <= L_DONE;
                    end else begin
                        l_char_idx <= l_char_idx + 6'd1;
                        l_state <= L_LOAD_CHAR;
                    end
                end

                L_DONE: begin
                    if (!start_question) begin
                        l_state <= L_IDLE;
                    end
                end

                default: l_state <= L_IDLE;
            endcase
        end
    end

endmodule