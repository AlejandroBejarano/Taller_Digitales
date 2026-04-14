`timescale 1ns / 1ps
// =============================================================================
// Proyecto : EL3313 Proyecto 2 - Jeopardy! (I Semestre 2026)
// Archivo  : lcd_newlogic.sv
// =============================================================================

// =============================================================================
// Modulo 1: lcd_question_rom
// =============================================================================
module lcd_question_rom #(
    parameter integer DEPTH    = 320,
    parameter integer WIDTH    = 8,
    parameter string  COE_FILE = "all_questions.coe"
)(
    input  logic                      clk,
    input  logic [$clog2(DEPTH)-1:0]  addr,   // 0..319
    output logic [WIDTH-1:0]          data_o
);

    // CAMBIO: Se cambio la inferencia de BRAM y $readmemh por la instanciacion
    // del IP de Vivado 'blk_mem_questions' porque $readmemh con archivos .coe 
    // no es soportado nativamente para simulacion y causaba valores XX.
    blk_mem_questions ip_rom_questions (
        .clka  (clk),
        .addra (addr),
        .douta (data_o)
    );

endmodule


// =============================================================================
// Modulo 2: lcd_option_rom
// =============================================================================
module lcd_option_rom #(
    parameter integer DEPTH    = 320,
    parameter integer WIDTH    = 8,
    parameter string  COE_FILE = "all_opt_questions.coe"
)(
    input  logic                      clk,
    input  logic [$clog2(DEPTH)-1:0]  addr,   // 0..319
    output logic [WIDTH-1:0]          data_o
);

    // CAMBIO: Se cambio la inferencia de BRAM y $readmemh por la instanciacion
    // del IP de Vivado 'blk_mem_options' porque $readmemh con archivos .coe 
    // no es soportado nativamente para simulacion y causaba valores XX.
    blk_mem_options ip_rom_options (
        .clka  (clk),
        .addra (addr),
        .douta (data_o)
    );

endmodule


// =============================================================================
// Modulo 3: lcd_register_file
// (Sin cambios estructurales, se mantiene identico al original)
// =============================================================================
module lcd_register_file (
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic        write_enable_i,
    input  logic [1:0]  addr_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    output logic        pulse_start,
    output logic        pulse_clear,
    output logic        pulse_home,
    output logic        reg_rs,
    output logic [7:0]  reg_data,
    input  logic        hw_busy,
    input  logic        hw_done
);
    logic done_flag;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            reg_rs      <= 1'b0;
            reg_data    <= 8'h00;
            pulse_start <= 1'b0;
            pulse_clear <= 1'b0;
            pulse_home  <= 1'b0;
            done_flag   <= 1'b0;
        end else begin
            pulse_start <= 1'b0;
            pulse_clear <= 1'b0;
            pulse_home  <= 1'b0;

            if (hw_done)
                done_flag <= 1'b1;

            if (write_enable_i) begin
                case (addr_i)
                    2'b00: begin 
                        pulse_start <= wdata_i[0]; 
                        reg_rs      <= wdata_i[1]; 
                        pulse_clear <= wdata_i[2]; 
                        pulse_home  <= wdata_i[3]; 
                        if (wdata_i[0] | wdata_i[2] | wdata_i[3])
                            done_flag <= 1'b0;
                    end
                    2'b01: begin 
                        reg_data <= wdata_i[7:0];  
                    end
                    default: ; 
                endcase
            end
        end
    end

    always_comb begin
        rdata_o = 32'h00000000;
        case (addr_i)
            2'b00: begin 
                rdata_o[1] = reg_rs;
                rdata_o[8] = hw_busy;   
                rdata_o[9] = done_flag; 
            end
            2'b01: begin 
                rdata_o[7:0] = reg_data;
            end
            default: rdata_o = 32'h00000000;
        endcase
    end
endmodule


// =============================================================================
// Modulo 4: lcd_driver_hw
// =============================================================================
// CAMBIO: Se agrego el parametro POWERON_US con valor por defecto 50000 porque
// permite al testbench sobreescribirlo a 100 para acelerar la simulacion sin 
// afectar el comportamiento real en hardware.
module lcd_driver_hw #(
    parameter integer POWERON_US = 50000
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       start_req,
    input  logic       clear_req,
    input  logic       home_req,
    input  logic [7:0] data_in,
    input  logic       rs_in,
    output logic       busy,
    output logic       done_pulse,
    output logic       lcd_rs,
    output logic       lcd_rw,
    output logic       lcd_e,
    output logic [7:0] lcd_d
);
    assign lcd_rw = 1'b0;

    localparam integer TICKS_PER_US = 16;
    logic [3:0] tick_cnt;
    logic       tick_1us;

    always_ff @(posedge clk) begin
        if (rst) begin
            tick_cnt <= 4'd0;
            tick_1us <= 1'b0;
        end else if (tick_cnt == TICKS_PER_US - 1) begin
            tick_cnt <= 4'd0;
            tick_1us <= 1'b1;
        end else begin
            tick_cnt <= tick_cnt + 1'b1;
            tick_1us <= 1'b0;
        end
    end

    typedef enum logic [2:0] {
        WAIT_DELAY,
        IDLE,
        SETUP,
        TOGGLE_E_HIGH,
        TOGGLE_E_LOW
    } drv_state_t;

    drv_state_t state;
    logic [19:0] delay;

    // CAMBIO: Se agrego exec_delay porque en el original SETUP sobreescribia
    // el delay asignado en IDLE con DELAY_ENABLE_US, causando que el tiempo de
    // ejecucion del comando no se respetara en TOGGLE_E_LOW.
    logic [19:0] exec_delay;

    // CAMBIO: DELAY_POWERON_US ahora usa el parametro POWERON_US
    localparam integer DELAY_POWERON_US = POWERON_US; 
    localparam integer DELAY_SLOW_US    = 20'd2000;  
    localparam integer DELAY_FAST_US    = 20'd50;    
    localparam integer DELAY_ENABLE_US  = 20'd2;     

    always_ff @(posedge clk) begin
        if (rst) begin
            state      <= WAIT_DELAY;
            busy       <= 1'b1;
            done_pulse <= 1'b0;
            lcd_e      <= 1'b0;
            lcd_rs     <= 1'b0;
            lcd_d      <= 8'h00;
            delay      <= DELAY_POWERON_US;
            exec_delay <= 20'd0; // CAMBIO: reset de exec_delay
        end else begin
            done_pulse <= 1'b0; 

            if (tick_1us) begin
                case (state)
                    IDLE: begin
                        busy <= 1'b0;
                        if (start_req | clear_req | home_req) begin
                            busy <= 1'b1;
                            if (clear_req) begin
                                lcd_rs <= 1'b0;
                                lcd_d  <= 8'h01; 
                                exec_delay <= DELAY_SLOW_US; // CAMBIO: Se guarda en exec_delay
                            end else if (home_req) begin
                                lcd_rs <= 1'b0;
                                lcd_d  <= 8'h02; 
                                exec_delay <= DELAY_SLOW_US; // CAMBIO: Se guarda en exec_delay
                            end else begin
                                lcd_rs <= rs_in;
                                lcd_d  <= data_in;
                                exec_delay <= (~rs_in & (data_in <= 8'h03)) ? DELAY_SLOW_US : DELAY_FAST_US; // CAMBIO: Se guarda en exec_delay
                            end
                            state <= SETUP;
                        end
                    end

                    SETUP: begin
                        lcd_e <= 1'b1;
                        delay <= DELAY_ENABLE_US;
                        state <= TOGGLE_E_HIGH;
                    end

                    TOGGLE_E_HIGH: begin
                        if (delay == 20'd0) begin
                            lcd_e <= 1'b0;
                            delay <= exec_delay; // CAMBIO: Se carga el exec_delay guardado para la fase LOW
                            state <= TOGGLE_E_LOW;
                        end else
                            delay <= delay - 1'b1;
                    end

                    TOGGLE_E_LOW: begin
                        if (delay == 20'd0) begin
                            done_pulse <= 1'b1;
                            state      <= IDLE;
                        end else
                            delay <= delay - 1'b1;
                    end

                    WAIT_DELAY: begin 
                        if (delay == 20'd0) begin
                            done_pulse <= 1'b1;
                            state      <= IDLE;
                        end else
                            delay <= delay - 1'b1;
                    end

                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule


// =============================================================================
// Modulo 5 (Top): lcd_peripheral
// =============================================================================
// CAMBIO: Se agrego el parametro POWERON_US para poder propagarlo al driver 
// fisico desde peripheral_top.
module lcd_peripheral #(
    parameter integer POWERON_US = 50000
)(
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic        write_enable_i,
    input  logic [1:0]  addr_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,

    output logic        lcd_rs,
    output logic        lcd_rw,
    output logic        lcd_e,
    output logic [7:0]  lcd_d,

    input  logic [3:0]  question_num,   
    input  logic [4:0]  question_off,   
    output logic [7:0]  question_byte_o,
    output logic [7:0]  option_byte_o
);

    logic        pulse_start, pulse_clear, pulse_home;
    logic        reg_rs;
    logic [7:0]  reg_data;
    logic        hw_busy, hw_done;

    logic [8:0] rom_addr;
    assign rom_addr = {question_num, question_off}; 

    lcd_question_rom #(
        .DEPTH    (320),
        .WIDTH    (8),
        .COE_FILE ("all_questions.coe")
    ) u_question_rom (
        .clk    (clk_i),
        .addr   (rom_addr),
        .data_o (question_byte_o)
    );

    lcd_option_rom #(
        .DEPTH    (320),
        .WIDTH    (8),
        .COE_FILE ("all_opt_questions.coe")
    ) u_option_rom (
        .clk    (clk_i),
        .addr   (rom_addr),
        .data_o (option_byte_o)
    );

    lcd_register_file u_regfile (
        .clk_i          (clk_i),
        .rst_i          (rst_i),
        .write_enable_i (write_enable_i),
        .addr_i         (addr_i),
        .wdata_i        (wdata_i),
        .rdata_o        (rdata_o),
        .pulse_start    (pulse_start),
        .pulse_clear    (pulse_clear),
        .pulse_home     (pulse_home),
        .reg_rs         (reg_rs),
        .reg_data       (reg_data),
        .hw_busy        (hw_busy),
        .hw_done        (hw_done)
    );

    // CAMBIO: Se instancio el driver pasando el parametro POWERON_US
    lcd_driver_hw #(
        .POWERON_US (POWERON_US)
    ) u_driver_hw (
        .clk        (clk_i),
        .rst        (rst_i),
        .start_req  (pulse_start),
        .clear_req  (pulse_clear),
        .home_req   (pulse_home),
        .data_in    (reg_data),
        .rs_in      (reg_rs),
        .busy       (hw_busy),
        .done_pulse (hw_done),
        .lcd_rs     (lcd_rs),
        .lcd_rw     (lcd_rw),
        .lcd_e      (lcd_e),
        .lcd_d      (lcd_d)
    );

endmodule