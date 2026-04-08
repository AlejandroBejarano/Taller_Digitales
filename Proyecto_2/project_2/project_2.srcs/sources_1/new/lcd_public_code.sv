//============================================================
// Digilent Pmod CLP (HD44780) 4-bit mode driver
// SystemVerilog - Synthesizable
// Writes "HELLO WORLD" to line 1
//============================================================
module pmod_clp_driver (
    input  logic        clk,        // System clock
    input  logic        reset_n,    // Active-low reset
    output logic [3:0]  lcd_data,   // LCD data lines D4-D7
    output logic        lcd_rs,     // Register Select
    output logic        lcd_rw,     // Read/Write (0 = write)
    output logic        lcd_en      // Enable strobe
);

    //========================================================
    // Parameters
    //========================================================
    parameter CLK_FREQ_HZ = 50_000_000; // FPGA clock frequency
    parameter INIT_DELAY  = 15_000;     // 15 ms after power-up
    parameter CMD_DELAY   = 2_000;      // 2 ms between commands
    parameter CHAR_DELAY  = 50;         // 50 us between characters

    //========================================================
    // State machine definitions
    //========================================================
    typedef enum logic [3:0] {
        S_INIT_WAIT,
        S_FUNC_SET1,
        S_FUNC_SET2,
        S_FUNC_SET3,
        S_FUNC_SET4,
        S_DISP_OFF,
        S_CLEAR,
        S_ENTRY_MODE,
        S_DISP_ON,
        S_WRITE_CHARS,
        S_DONE
    } state_t;

    state_t state, next_state;

    //========================================================
    // Delay counter
    //========================================================
    logic [31:0] delay_cnt;
    logic delay_done;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            delay_cnt <= 0;
        else if (!delay_done)
            delay_cnt <= delay_cnt + 1;
        else
            delay_cnt <= 0;
    end

    assign delay_done = (state == S_INIT_WAIT  && delay_cnt >= (CLK_FREQ_HZ/1000)*INIT_DELAY/1000) ||
                        (state != S_INIT_WAIT && delay_cnt >= (CLK_FREQ_HZ/1000)*CMD_DELAY/1000);

    //========================================================
    // LCD control signals
    //========================================================
    logic [7:0] char_data [0:10]; // "HELLO WORLD"
    initial begin
        char_data[0]  = "H";
        char_data[1]  = "E";
        char_data[2]  = "L";
        char_data[3]  = "L";
        char_data[4]  = "O";
        char_data[5]  = " ";
        char_data[6]  = "W";
        char_data[7]  = "O";
        char_data[8]  = "R";
        char_data[9]  = "L";
        char_data[10] = "D";
    end

    logic [3:0] nibble;
    logic [3:0] char_idx;
    logic       send_high;

    //========================================================
    // FSM: State transitions
    //========================================================
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            state <= S_INIT_WAIT;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            S_INIT_WAIT:   if (delay_done) next_state = S_FUNC_SET1;
            S_FUNC_SET1:   if (delay_done) next_state = S_FUNC_SET2;
            S_FUNC_SET2:   if (delay_done) next_state = S_FUNC_SET3;
            S_FUNC_SET3:   if (delay_done) next_state = S_FUNC_SET4;
            S_FUNC_SET4:   if (delay_done) next_state = S_DISP_OFF;
            S_DISP_OFF:    if (delay_done) next_state = S_CLEAR;
            S_CLEAR:       if (delay_done) next_state = S_ENTRY_MODE;
            S_ENTRY_MODE:  if (delay_done) next_state = S_DISP_ON;
            S_DISP_ON:     if (delay_done) next_state = S_WRITE_CHARS;
            S_WRITE_CHARS: if (char_idx > 10) next_state = S_DONE;
            S_DONE:        next_state = S_DONE;
        endcase
    end

    //========================================================
    // LCD command/data sending
    //========================================================
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            lcd_rs     <= 0;
            lcd_rw     <= 0;
            lcd_en     <= 0;
            lcd_data   <= 0;
            char_idx   <= 0;
            send_high  <= 1;
        end else begin
            case (state)
                S_FUNC_SET1: send_command(8'h33); // Init 4-bit
                S_FUNC_SET2: send_command(8'h32); // Set 4-bit mode
                S_FUNC_SET3: send_command(8'h28); // 2 lines, 5x8 font
                S_FUNC_SET4: send_command(8'h28);
                S_DISP_OFF:  send_command(8'h08); // Display off
                S_CLEAR:     send_command(8'h01); // Clear display
                S_ENTRY_MODE:send_command(8'h06); // Entry mode
                S_DISP_ON:   send_command(8'h0C); // Display on
                S_WRITE_CHARS: begin
                    send_data(char_data[char_idx]);
                    if (delay_cnt >= (CLK_FREQ_HZ/1000)*CHAR_DELAY/1000) begin
                        char_idx <= char_idx + 1;
                    end
                end
                default: ;
            endcase
        end
    end

    //========================================================
    // Tasks for sending commands/data
    //========================================================
    task send_command(input [7:0] cmd);
        begin
            lcd_rs <= 0; // Command mode
            send_byte(cmd);
        end
    endtask

    task send_data(input [7:0] data);
        begin
            lcd_rs <= 1; // Data mode
            send_byte(data);
        end
    endtask

    task send_byte(input [7:0] byte);
        begin
            // Send high nibble
            lcd_data <= byte[7:4];
            lcd_en   <= 1; #1 lcd_en <= 0;
            // Send low nibble
            lcd_data <= byte[3:0];
            lcd_en   <= 1; #1 lcd_en <= 0;
        end
    endtask

endmodule
