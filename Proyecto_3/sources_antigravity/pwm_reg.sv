//==============================================================================
// File   : pwm_regs.sv
// Module : pwm_regs
// Desc   : Interfaz de registros (CONTROLPATH) del periférico PWM mapeado en
//          memoria. Implementa los dos registros de 32 bits especificados:
//
//            CTRL/STATUS  @ offset 0x00 (sistema: 0x0001_0100)
//              bit 0      : enable      (R/W)
//              bits [2:1] : freq_sel    (R/W)  - 4 frecuencias válidas
//              bit 3      : running     (RO)   - viene del datapath
//              bits [31:4]: reservados  (lectura = 0, escritura ignorada)
//
//            DUTY         @ offset 0x04 (sistema: 0x0001_0104)
//              bits [6:0] : duty_pct    (R/W)  - 0..100, satura
//              bits [31:7]: reservados
//
// Notas  : - El módulo recibe un chip-select (cs_i) generado por el bus
//            interconnect. Internamente sólo usa el offset (addr_i[3:0]).
//          - rdata_o = 0 cuando cs_i = 0, para permitir OR-mux externo.
//          - Reset síncrono (recomendado para FPGAs Xilinx Artix-7).
//==============================================================================
module pwm_regs (
    input  logic        clk_i,
    input  logic        rst_i,         // reset síncrono activo en alto

    // Interfaz de bus (slave). El cs_i lo genera el address decoder externo.
    input  logic        cs_i,          // chip select del periférico
    input  logic [3:0]  addr_i,        // offset dentro del periférico (0x0..0x4)
    input  logic        we_i,          // write enable (1=escritura, 0=lectura)
    input  logic [31:0] wdata_i,       // dato a escribir desde la CPU
    output logic [31:0] rdata_o,       // dato leído hacia la CPU

    // Hacia/desde el datapath (pwm_core)
    output logic        enable_o,      // habilita la generación PWM
    output logic [1:0]  freq_sel_o,    // selección de frecuencia
    output logic [6:0]  duty_pct_o,    // ciclo de trabajo en % (0..100)
    input  logic        running_i      // estado real del generador
);

    //--------------------------------------------------------------------------
    // Offsets de los registros del periférico
    //--------------------------------------------------------------------------
    localparam logic [3:0] OFFSET_CTRL = 4'h0;
    localparam logic [3:0] OFFSET_DUTY = 4'h4;

    //--------------------------------------------------------------------------
    // Registros internos
    //--------------------------------------------------------------------------
    logic        enable_r;
    logic [1:0]  freq_sel_r;
    logic [6:0]  duty_pct_r;

    //--------------------------------------------------------------------------
    // Lógica de escritura (registrada). Saturación del duty al rango [0,100].
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            enable_r   <= 1'b0;
            freq_sel_r <= 2'b00;        // arranca en la frecuencia más baja
            duty_pct_r <= 7'd0;         // arranca con duty = 0% (seguro)
        end
        else if (cs_i && we_i) begin
            unique case (addr_i)
                OFFSET_CTRL: begin
                    enable_r   <= wdata_i[0];
                    freq_sel_r <= wdata_i[2:1];
                    // bit 3 (running) es RO  -> ignorar
                    // bits [31:4] reservados -> ignorar
                end

                OFFSET_DUTY: begin
                    // Saturación: si el valor escrito (32 bits) excede 100,
                    // se fija en 100. En otro caso se toman los 7 LSB.
                    if (wdata_i > 32'd100)
                        duty_pct_r <= 7'd100;
                    else
                        duty_pct_r <= wdata_i[6:0];
                end

                default: ; // otros offsets dentro del rango: sin efecto
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Lógica de lectura (combinacional). Devuelve 0 cuando no está seleccionado
    // para permitir un OR-mux a nivel de bus interconnect.
    //--------------------------------------------------------------------------
    always_comb begin
        rdata_o = 32'h0000_0000;
        if (cs_i && !we_i) begin
            unique case (addr_i)
                OFFSET_CTRL: rdata_o = {28'd0, running_i, freq_sel_r, enable_r};
                OFFSET_DUTY: rdata_o = {25'd0, duty_pct_r};
                default    : rdata_o = 32'h0000_0000;
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Conexiones hacia el datapath
    //--------------------------------------------------------------------------
    assign enable_o   = enable_r;
    assign freq_sel_o = freq_sel_r;
    assign duty_pct_o = duty_pct_r;

endmodule