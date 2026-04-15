// =============================================================================
// hardware_peripherals.sv — Módulos de hardware de bajo nivel para Jeopardy
//
// Contiene tres módulos independientes:
//
//   debouncer       – Elimina el rebote mecánico de un botón.
//   segments        – Multiplexor de display 7-seg de 4 dígitos (timer + puntos).
//   lcd_peripheral  – Periférico LCD HD44780 con bus de 32 bits tipo memoria.
//   lcd_driver      – Driver físico HD44780: genera pulsos EN y secuencia de init.
//
// Jerarquía: lcd_peripheral instancia a lcd_driver.
//            jeopardy_top / peripheral_top instancian debouncer, segments y lcd_peripheral.
// =============================================================================
`timescale 1ns / 1ps

// =============================================================================
// debouncer — Eliminador de rebote para botones mecánicos
//
// Propósito:
//   Filtra el ruido eléctrico (bouncing) de un botón mediante un contador.
//   Solo actualiza btn_out cuando la entrada ha permanecido estable por
//   COUNT_MAX ciclos de reloj consecutivos.
//
// Entradas:
//   clk     – Reloj del sistema.
//   reset   – Reset activo alto; fuerza btn_out=0.
//   btn_in  – Señal cruda del botón (puede tener rebote).
//
// Salidas:
//   btn_out – Señal limpia (debounced), 1 = botón presionado, 0 = suelto.
//
// Parámetro:
//   COUNT_MAX – Número de ciclos de estabilidad requeridos. En hardware real
//               usar 1,000,000 (≈62.5 ms a 16 MHz); en simulación usar 20.
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
// segments — Display 7-segmentos multiplexado de 4 dígitos
//
// Propósito:
//   Muestra en 4 dígitos del display 7-seg de la Basys3 los valores:
//     Dígito 3 (izquierda): decenas del timer (0-3)
//     Dígito 2:             unidades del timer (0-9)
//     Dígito 1:             puntaje del jugador FPGA (0-9)
//     Dígito 0 (derecha):   puntaje del jugador PC (0-9)
//
//   La multiplexación rota entre los 4 ánodos cada MUX_DIV ciclos de reloj
//   (4000 ciclos ≈ 250 µs a 16 MHz → ~4 kHz de refresco).
//
// Entradas:
//   clk_i        – Reloj del sistema (16 MHz).
//   rst_i        – Reset activo alto; apaga todos los segmentos.
//   timer_i      – Tiempo restante en segundos (0-30); se limita a 30.
//   score_fpga_i – Puntuación del jugador FPGA (0-9).
//   score_pc_i   – Puntuación del jugador PC (0-9).
//
// Salidas:
//   seg_o – Segmentos a encender (activo bajo, bits: G F E D C B A).
//   an_o  – Ánodos activos (activo bajo; solo uno en 0 a la vez).
//   dp_o  – Punto decimal (siempre apagado = 1 activo-bajo).
//
// Variables internas:
//   mux_cnt    – Contador de refresco (0..MUX_DIV-1).
//   digit_sel  – Dígito activo actual (3=izq → 0=der, decrementa cada MUX_DIV ciclos).
//   timer_safe – Valor del timer clampado a 30.
//   timer_tens / timer_units – Descomposición BCD del timer.
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
// lcd_peripheral — Periférico LCD HD44780 con bus de 32 bits tipo memoria
//
// Propósito:
//   Traduce escrituras del bus de 32 bits (addr+wdata) en comandos para
//   el driver físico HD44780 (lcd_driver). Actúa como controlador de
//   nivel medio: mantiene registros de control y datos, y genera los
//   pulsos de 1 ciclo que lcd_driver necesita.
//
// Mapa de registros (addr_i):
//   2'b00 (CTRL) — escritura:
//       bit0 = 1 → cmd_start (enviar byte en reg_data_byte al LCD)
//       bit1     → reg_rs (0=comando, 1=dato de carácter)
//       bit2 = 1 → cmd_clear (limpiar pantalla)
//       bit3 = 1 → cmd_home  (cursor al inicio)
//              *** Solo se activan si el driver NO está ocupado ***
//             lectura:
//       bit0     → reg_rs actual
//       bit7     → drv_busy (driver ocupado)
//       bit15    → flag_done (última operación terminó)
//   2'b01 (DATA) — escritura: carga reg_data_byte con wdata[7:0]
//                — lectura:  {24'd0, reg_data_byte}
//
// Entradas:
//   clk_i          – Reloj del sistema (16 MHz).
//   rst_i          – Reset activo alto.
//   write_enable_i – 1 = hay escritura en el bus este ciclo.
//   addr_i         – Registro destino (ver mapa arriba).
//   wdata_i        – Dato a escribir (32 bits).
//
// Salidas:
//   rdata_o        – Lectura del registro apuntado.
//   lcd_rs_o       – RS al LCD (0=comando, 1=dato).
//   lcd_rw_o       – RW al LCD (siempre 0 = escritura).
//   lcd_en_o       – Enable al LCD (pulso de sincronización).
//   lcd_data_o     – Bus de datos de 8 bits al LCD.
//
// Variables internas:
//   reg_rs         – Copia del bit RS más reciente.
//   reg_data_byte  – Byte a enviar al LCD.
//   flag_done      – Latch: se activa cuando lcd_driver señaliza done.
//   ctrl_start_w1p / ctrl_clear_w1p / ctrl_home_w1p – Pulsos de 1 ciclo
//                   que se generan si el driver no está ocupado.
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
// lcd_driver — Driver físico para LCD compatible HD44780 (modo 8 bits)
//
// Propósito:
//   Genera la secuencia de inicialización requerida por el HD44780 al encendido
//   y, una vez listo (S_READY), acepta comandos de escritura individuales.
//   Produce los pulsos físicos RS, RW, EN y el bus de 8 bits de datos.
//
// Secuencia de inicialización (automática al salir de reset):
//   S_POWERON     – Espera 40 ms (640k ciclos) tras encendido.
//   S_INIT_FS1-4  – Envía Function Set 0x30 × 3 + 0x38 (8 bits, 2 líneas, 5×8).
//   S_INIT_DC     – Display ON, cursor OFF (0x0C).
//   S_INIT_CLR    – Clear Display (0x01).
//   S_INIT_EM     – Entry Mode Set (0x06: incrementar cursor, no shift).
//   → S_READY (lcd_busy_o = 0; listo para recibir comandos).
//
// Ciclo de escritura de un byte (states S_SETUP → S_DONE):
//   S_SETUP    – Carga RS, RW y el dato en los pines.
//   S_EN_HIGH  – Pulso EN a 1 por T_EN_HIGH ciclos (≥450 ns).
//   S_EN_LOW   – Espera T_EN_SETTLE tras bajar EN.
//   S_CMD_WAIT – Espera hasta que el LCD procese: T_CMD (800 ciclos ≈50 µs)
//                o T_CLEAR (25600 ciclos ≈1.6 ms) para Clear/Home.
//   S_DONE     – Genera done_pulse=1 por 1 ciclo, regresa a S_READY.
//
// Entradas:
//   clk          – Reloj del sistema (16 MHz).
//   rst          – Reset activo alto; reinicia secuencia de inicialización.
//   cmd_data_i   – Byte a enviar (comando o dato ASCII).
//   cmd_rs_i     – 0=comando, 1=dato de carácter.
//   cmd_start_i  – Pulso de 1 ciclo: iniciar transferencia de cmd_data_i.
//   cmd_clear_i  – Pulso de 1 ciclo: enviar Clear Display (0x01).
//   cmd_home_i   – Pulso de 1 ciclo: enviar Return Home (0x02).
//
// Salidas:
//   lcd_busy_o   – 1 mientras el driver está inicializando o procesando.
//   lcd_done_o   – Pulso de 1 ciclo: el último comando terminó.
//   lcd_rs_o     – RS al LCD.
//   lcd_rw_o     – RW al LCD (siempre 0).
//   lcd_en_o     – Enable al LCD.
//   lcd_data_o   – Bus de datos D7-D0 al LCD.
//
// Variables internas:
//   delay_cnt    – Contador de ciclos para temporización.
//   delay_target – Período de espera en S_CMD_WAIT (T_CMD o T_CLEAR).
//   lcd_data_reg – Dato latcheado al inicio del ciclo de escritura.
//   lcd_rs_reg   – RS latcheado al inicio del ciclo de escritura.
//   is_clear_home– 1 si el comando es Clear o Home (espera T_CLEAR en CMD_WAIT).
//   done_pulse   – Genera lcd_done_o por 1 ciclo.
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

