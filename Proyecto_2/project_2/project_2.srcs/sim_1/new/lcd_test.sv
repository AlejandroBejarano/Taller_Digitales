`timescale 1ns / 1ps

module pmod_lcd (
    input  logic clk,
    output logic lcd_rs,
    output logic lcd_rw,
    output logic lcd_e,
    output logic [7:0] lcd_d
);

    assign lcd_rw = 1'b0; // Siempre escribimos

    // Base de tiempo de 1 microsegundo
    logic [6:0] tick_cnt = 0;
    logic tick_1us = 0;

    always_ff @(posedge clk) begin
        if (tick_cnt == 99) begin
            tick_cnt <= 0;
            tick_1us <= 1'b1;
        end else begin
            tick_cnt <= tick_cnt + 1;
            tick_1us <= 1'b0;
        end
    end

    // ROM ampliada a 28 instrucciones
    logic [8:0] seq [0:27];

    initial begin
        $readmemh("lcd_seq.mem", seq);
    end

    typedef enum logic [2:0] {
        POWER_ON, SET_DATA, TOGGLE_E_HIGH, TOGGLE_E_LOW, DONE
    } state_t;

    state_t state = POWER_ON;
    logic [4:0] seq_idx = 0;
    logic [19:0] delay = 50000; // 50ms para estabilización de VCC inicial

    always_ff @(posedge clk) begin
        if (tick_1us) begin
            if (delay > 0) begin
                delay <= delay - 1;
            end else begin
                case (state)
                    POWER_ON: begin
                        state <= SET_DATA;
                    end
                    SET_DATA: begin
                        if (seq_idx < 28) begin
                            lcd_rs <= seq[seq_idx][8];
                            lcd_d  <= seq[seq_idx][7:0];
                            lcd_e  <= 1'b0;
                            delay  <= 1; // 1us Setup Time
                            state  <= TOGGLE_E_HIGH;
                        end else begin
                            state <= DONE;
                        end
                    end
                    TOGGLE_E_HIGH: begin
                        lcd_e <= 1'b1;
                        delay <= 2; // Ancho del pulso E
                        state <= TOGGLE_E_LOW;
                    end
                    TOGGLE_E_LOW: begin
                        lcd_e <= 1'b0;
                        
                        // Diferentes tiempos de espera según la instrucción enviada
                        if (seq_idx == 0)      delay <= 5000; // Primer wake-up necesita >4.1ms
                        else if (seq_idx == 1) delay <= 200;  // Segundo wake-up necesita >100us
                        else if (seq[seq_idx][8] == 0 && seq[seq_idx][7:0] == 8'h01) 
                                               delay <= 2000; // El Clear Display necesita ~1.52ms
                        else                   delay <= 50;   // Demás comandos ocupan ~40us

                        seq_idx <= seq_idx + 1;
                        state   <= SET_DATA;
                    end
                    DONE: begin
                        lcd_e <= 1'b0;
                    end
                endcase
            end
        end
    end
endmodule