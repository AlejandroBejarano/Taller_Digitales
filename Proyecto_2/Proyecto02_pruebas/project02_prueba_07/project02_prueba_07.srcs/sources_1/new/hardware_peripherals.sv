// =============================================================================
// hardware_peripherals.sv - Módulos de hardware de bajo nivel para Jeopardy
// (Display 7-seg, LCD driver HD44780, y Debouncer)
// =============================================================================
`timescale 1ns / 1ps

// =============================================================================
// Debouncer
// =============================================================================
module debouncer (
    input logic clk,
    input logic reset,
    input logic btn_in,
    output logic btn_out
);
    parameter COUNT_MAX = 20; // 1,000,000 para hw real

    logic [19:0] counter = 0;
    logic btn_sync_0, btn_sync_1;

    always_ff @(posedge clk) begin
        btn_sync_0 <= btn_in;
        btn_sync_1 <= btn_sync_0;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            counter <= 0;
            btn_out <= 0;
        end else begin
            if (btn_sync_1 != btn_out) begin
                if (counter >= COUNT_MAX) begin
                    counter <= 0;
                    btn_out <= btn_sync_1; 
                end else begin
                    counter <= counter + 1;
                end
            end else begin
                counter <= 0; 
            end
        end
    end
endmodule


// =============================================================================
// Segments (Multiplexor de 4 Anodes)
// =============================================================================
module segments (
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic [5:0]  timer_i,
    input  logic [3:0]  score_fpga_i,
    input  logic [3:0]  score_pc_i,
    output logic [6:0]  seg_o,
    output logic [3:0]  an_o,
    output logic        dp_o
);
    assign dp_o = 1'b1;
    localparam integer MUX_DIV = 4000;
    logic [11:0] mux_cnt;
    logic [1:0]  digit_sel;

    logic [5:0] timer_safe;
    logic [3:0] timer_tens;
    logic [5:0] timer_remainder;
    logic [3:0] timer_units;

    assign timer_safe      = (timer_i > 6'd30) ? 6'd30 : timer_i;
    assign timer_tens      = (timer_safe >= 6'd30) ? 4'd3 :
                             (timer_safe >= 6'd20) ? 4'd2 :
                             (timer_safe >= 6'd10) ? 4'd1 : 4'd0;
    assign timer_remainder = (timer_tens == 4'd3) ? 6'd30 : 
                             (timer_tens == 4'd2) ? 6'd20 :
                             (timer_tens == 4'd1) ? 6'd10 : 6'd0;
    assign timer_units     = timer_safe - timer_remainder;

    logic [3:0] digit_to_display;

    always_comb begin
        case (digit_sel)
            2'd3: digit_to_display = timer_tens;
            2'd2: digit_to_display = timer_units;
            2'd1: digit_to_display = score_fpga_i;
            2'd0: digit_to_display = score_pc_i;
            default: digit_to_display = 4'd15;
        endcase
    end

    logic [6:0] seg;
    always_comb begin
        case (digit_to_display)
            4'd0: seg = 7'b1000000; // Inverted for Active Low (G es idx 6, F 5, E 4, D 3, C 2, B 1, A 0)
            4'd1: seg = 7'b1111001; 
            4'd2: seg = 7'b0100100;
            4'd3: seg = 7'b0110000;
            4'd4: seg = 7'b0011001;
            4'd5: seg = 7'b0010010;
            4'd6: seg = 7'b0000010;
            4'd7: seg = 7'b1111000;
            4'd8: seg = 7'b0000000;
            4'd9: seg = 7'b0010000;
            default: seg = 7'b1111111;
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            mux_cnt   <= 12'd0;
            digit_sel <= 2'd3;
        end else begin
            if (mux_cnt == MUX_DIV - 1) begin
                mux_cnt   <= 12'd0;
                digit_sel <= digit_sel - 2'd1;
            end else begin
                mux_cnt <= mux_cnt + 12'd1;
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            seg_o <= 7'b1111111;
            an_o  <= 4'b1111;
        end else begin
            seg_o <= seg;
            case (digit_sel)
                2'd3: an_o <= 4'b0111;
                2'd2: an_o <= 4'b1011;
                2'd1: an_o <= 4'b1101;
                2'd0: an_o <= 4'b1110;
                default: an_o <= 4'b1111;
            endcase
        end
    end
endmodule


// =============================================================================
// LCD PERIPHERAL
// =============================================================================
module lcd_peripheral (
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic        write_enable_i,
    input  logic [1:0]  addr_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,

    output logic        lcd_rs_o,
    output logic        lcd_rw_o,
    output logic        lcd_en_o,
    output logic [7:0]  lcd_data_o
);
    logic       reg_rs;
    logic [7:0] reg_data_byte;
    logic       flag_done;

    logic       drv_busy, drv_done;
    logic       drv_start, drv_clear, drv_home;

    logic       ctrl_start_w1p;
    logic       ctrl_clear_w1p;
    logic       ctrl_home_w1p;

    lcd_driver u_drv (
        .clk         (clk_i),
        .rst         (rst_i),
        .cmd_data_i  (reg_data_byte),
        .cmd_rs_i    (reg_rs),
        .cmd_start_i (drv_start),
        .cmd_clear_i (drv_clear),
        .cmd_home_i  (drv_home),
        .lcd_busy_o  (drv_busy),
        .lcd_done_o  (drv_done),
        .lcd_rs_o    (lcd_rs_o),
        .lcd_rw_o    (lcd_rw_o),
        .lcd_en_o    (lcd_en_o),
        .lcd_data_o  (lcd_data_o)
    );

    assign drv_start = ctrl_start_w1p;
    assign drv_clear = ctrl_clear_w1p;
    assign drv_home  = ctrl_home_w1p;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            reg_rs          <= 1'b0;
            reg_data_byte   <= 8'h00;
            ctrl_start_w1p  <= 1'b0;
            ctrl_clear_w1p  <= 1'b0;
            ctrl_home_w1p   <= 1'b0;
            flag_done       <= 1'b0;
        end else begin
            ctrl_start_w1p <= 1'b0;
            ctrl_clear_w1p <= 1'b0;
            ctrl_home_w1p  <= 1'b0;

            if (drv_done) flag_done <= 1'b1;

            if (write_enable_i) begin
                case (addr_i)
                    2'b00: begin
                        if (wdata_i[0] && !drv_busy) ctrl_start_w1p <= 1'b1;
                        reg_rs         <= wdata_i[1];
                        if (wdata_i[2] && !drv_busy) ctrl_clear_w1p <= 1'b1;
                        if (wdata_i[3] && !drv_busy) ctrl_home_w1p  <= 1'b1;
                    end
                    2'b01: begin
                        reg_data_byte <= wdata_i[7:0];
                    end
                    default: ;
                endcase
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (!rst_i && (!write_enable_i && addr_i == 2'b00)) begin
            flag_done <= 1'b0;
        end
    end

    always_comb begin
        case (addr_i)
            2'b00: rdata_o = {15'b0, flag_done, 7'b0, drv_busy, 4'b0, 1'b0, 1'b0, reg_rs, 1'b0};
            2'b01: rdata_o = {24'b0, reg_data_byte};
            default: rdata_o = 32'h0000_0000;
        endcase
    end
endmodule


// =============================================================================
// LCD DRIVER HD44780
// =============================================================================
module lcd_driver (
    input  logic        clk,
    input  logic        rst,
    input  logic [7:0]  cmd_data_i,
    input  logic        cmd_rs_i,
    input  logic        cmd_start_i,
    input  logic        cmd_clear_i,
    input  logic        cmd_home_i,
    output logic        lcd_busy_o,
    output logic        lcd_done_o,
    output logic        lcd_rs_o,
    output logic        lcd_rw_o,
    output logic        lcd_en_o,
    output logic [7:0]  lcd_data_o
);
    localparam int T_POWERON   = 640_000; 
    localparam int T_INIT1     =  66_000; 
    localparam int T_INIT2     =   2_000; 
    localparam int T_INIT3     =   2_000; 
    localparam int T_EN_HIGH   =      16; 
    localparam int T_EN_SETTLE =      20; 
    localparam int T_CMD       =     800; 
    localparam int T_CLEAR     =  25_600; 

    typedef enum logic [4:0] {
        S_POWERON       = 5'd0,
        S_INIT_FS1_EN   = 5'd1, S_INIT_FS1_WAIT = 5'd2,
        S_INIT_FS2_EN   = 5'd3, S_INIT_FS2_WAIT = 5'd4,
        S_INIT_FS3_EN   = 5'd5, S_INIT_FS3_WAIT = 5'd6,
        S_INIT_FS4_EN   = 5'd7, S_INIT_FS4_WAIT = 5'd8,
        S_INIT_DC_EN    = 5'd9, S_INIT_DC_WAIT  = 5'd10,
        S_INIT_CLR_EN   = 5'd11,S_INIT_CLR_WAIT = 5'd12,
        S_INIT_EM_EN    = 5'd13,S_INIT_EM_WAIT  = 5'd14,
        S_READY         = 5'd15,
        S_SETUP         = 5'd16, S_EN_HIGH       = 5'd17,
        S_EN_LOW        = 5'd18, S_CMD_WAIT      = 5'd19,
        S_DONE          = 5'd20
    } state_t;

    state_t state;
    logic [19:0] delay_cnt;
    logic [19:0] delay_target;
    logic [7:0]  lcd_data_reg;
    logic        lcd_rs_reg;
    logic        is_clear_home;
    logic        done_pulse;

    always_ff @(posedge clk) begin
        if (rst) begin
            state        <= S_POWERON;
            delay_cnt    <= '0;
            delay_target <= T_POWERON[19:0];
            lcd_rs_reg   <= 1'b0;
            lcd_data_reg <= 8'h00;
            lcd_rs_o     <= 1'b0;
            lcd_rw_o     <= 1'b0;
            lcd_en_o     <= 1'b0;
            lcd_data_o   <= 8'h00;
            lcd_busy_o   <= 1'b1;
            done_pulse   <= 1'b0;
            is_clear_home<= 1'b0;
        end else begin
            done_pulse <= 1'b0;

            case (state)
                S_POWERON: begin
                    lcd_busy_o <= 1'b1;
                    if (delay_cnt == T_POWERON[19:0] - 1) begin
                        delay_cnt <= '0;
                        state     <= S_INIT_FS1_EN;
                    end else delay_cnt <= delay_cnt + 1;
                end
                S_INIT_FS1_EN: begin
                    lcd_rs_o <= 1'b0; lcd_data_o <= 8'h30; lcd_en_o <= 1'b1;
                    delay_cnt <= '0; state <= S_INIT_FS1_WAIT;
                end
                S_INIT_FS1_WAIT: begin
                    if (delay_cnt == T_EN_HIGH - 1) begin
                        lcd_en_o <= 1'b0; delay_cnt <= '0; state <= S_INIT_FS2_EN;
                    end else delay_cnt <= delay_cnt + 1;
                end
                S_INIT_FS2_EN: begin
                    if (delay_cnt == T_INIT1[19:0] - 1) begin
                        lcd_en_o <= 1'b1; lcd_data_o <= 8'h30; delay_cnt <= '0; state <= S_INIT_FS2_WAIT;
                    end else delay_cnt <= delay_cnt + 1;
                end
                S_INIT_FS2_WAIT: begin
                    if (delay_cnt == T_EN_HIGH - 1) begin
                        lcd_en_o <= 1'b0; delay_cnt <= '0; state <= S_INIT_FS3_EN;
                    end else delay_cnt <= delay_cnt + 1;
                end
                S_INIT_FS3_EN: begin
                    if (delay_cnt == T_INIT2[19:0] - 1) begin
                        lcd_en_o <= 1'b1; lcd_data_o <= 8'h30; delay_cnt <= '0; state <= S_INIT_FS3_WAIT;
                    end else delay_cnt <= delay_cnt + 1;
                end
                S_INIT_FS3_WAIT: begin
                    if (delay_cnt == T_EN_HIGH - 1) begin
                        lcd_en_o <= 1'b0; delay_cnt <= '0; state <= S_INIT_FS4_EN;
                    end else delay_cnt <= delay_cnt + 1;
                end
                S_INIT_FS4_EN: begin
                    if (delay_cnt == T_INIT3[19:0] - 1) begin
                        lcd_rs_o <= 1'b0; lcd_data_o <= 8'h38; lcd_en_o <= 1'b1; delay_cnt <= '0; state <= S_INIT_FS4_WAIT;
                    end else delay_cnt <= delay_cnt + 1;
                end
                S_INIT_FS4_WAIT: begin
                    if (delay_cnt == T_EN_HIGH - 1) begin
                        lcd_en_o <= 1'b0; delay_cnt <= '0; state <= S_INIT_DC_EN;
                    end else delay_cnt <= delay_cnt + 1;
                end
                S_INIT_DC_EN: begin
                    if (delay_cnt == T_CMD[19:0] - 1) begin
                        lcd_rs_o <= 1'b0; lcd_data_o <= 8'h0C; lcd_en_o <= 1'b1; delay_cnt <= '0; state <= S_INIT_DC_WAIT;
                    end else delay_cnt <= delay_cnt + 1;
                end
                S_INIT_DC_WAIT: begin
                    if (delay_cnt == T_EN_HIGH - 1) begin
                        lcd_en_o <= 1'b0; delay_cnt <= '0; state <= S_INIT_CLR_EN;
                    end else delay_cnt <= delay_cnt + 1;
                end
                S_INIT_CLR_EN: begin
                    if (delay_cnt == T_CMD[19:0] - 1) begin
                        lcd_rs_o <= 1'b0; lcd_data_o <= 8'h01; lcd_en_o <= 1'b1; delay_cnt <= '0; state <= S_INIT_CLR_WAIT;
                    end else delay_cnt <= delay_cnt + 1;
                end
                S_INIT_CLR_WAIT: begin
                    if (delay_cnt == T_EN_HIGH - 1) begin
                        lcd_en_o <= 1'b0; delay_cnt <= '0; state <= S_INIT_EM_EN;
                    end else delay_cnt <= delay_cnt + 1;
                end
                S_INIT_EM_EN: begin
                    if (delay_cnt == T_CLEAR[19:0] - 1) begin
                        lcd_rs_o <= 1'b0; lcd_data_o <= 8'h06; lcd_en_o <= 1'b1; delay_cnt <= '0; state <= S_INIT_EM_WAIT;
                    end else delay_cnt <= delay_cnt + 1;
                end
                S_INIT_EM_WAIT: begin
                    if (delay_cnt == T_EN_HIGH - 1) begin
                        lcd_en_o <= 1'b0; delay_cnt <= '0; lcd_busy_o <= 1'b0; state <= S_READY;
                    end else delay_cnt <= delay_cnt + 1;
                end
                S_READY: begin
                    lcd_busy_o <= 1'b0;
                    if (cmd_clear_i) begin
                        lcd_data_reg <= 8'h01; lcd_rs_reg <= 1'b0; is_clear_home <= 1'b1; lcd_busy_o <= 1'b1; state <= S_SETUP;
                    end else if (cmd_home_i) begin
                        lcd_data_reg <= 8'h02; lcd_rs_reg <= 1'b0; is_clear_home <= 1'b1; lcd_busy_o <= 1'b1; state <= S_SETUP;
                    end else if (cmd_start_i) begin
                        lcd_data_reg <= cmd_data_i; lcd_rs_reg <= cmd_rs_i; is_clear_home <= 1'b0; lcd_busy_o <= 1'b1; state <= S_SETUP;
                    end
                end
                S_SETUP: begin
                    lcd_rs_o <= lcd_rs_reg; lcd_rw_o <= 1'b0; lcd_data_o <= lcd_data_reg;
                    delay_cnt <= '0; state <= S_EN_HIGH;
                end
                S_EN_HIGH: begin
                    lcd_en_o <= 1'b1;
                    if (delay_cnt == T_EN_HIGH - 1) begin
                        lcd_en_o <= 1'b0; delay_cnt <= '0; state <= S_EN_LOW;
                    end else delay_cnt <= delay_cnt + 1;
                end
                S_EN_LOW: begin
                    if (delay_cnt == T_EN_SETTLE - 1) begin
                        delay_cnt <= '0; delay_target <= is_clear_home ? T_CLEAR[19:0] : T_CMD[19:0]; state <= S_CMD_WAIT;
                    end else delay_cnt <= delay_cnt + 1;
                end
                S_CMD_WAIT: begin
                    if (delay_cnt == delay_target - 1) begin
                        delay_cnt <= '0; state <= S_DONE;
                    end else delay_cnt <= delay_cnt + 1;
                end
                S_DONE: begin
                    done_pulse <= 1'b1; state <= S_READY;
                end
                default: state <= S_READY;
            endcase
        end
    end

    assign lcd_done_o = done_pulse;
endmodule

