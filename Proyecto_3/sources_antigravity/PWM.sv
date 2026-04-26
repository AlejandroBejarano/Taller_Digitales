//==============================================================================
// File   : pwm_top.sv
// Module : pwm_top
// Desc   : Top-level del periférico PWM mapeado en memoria. Integra:
//
//             pwm_regs  (controlpath) <--+
//                                        |  enable, freq_sel, duty_pct, running
//             pwm_core  (datapath)   <---+
//
//          Interfaz externa:
//          ----------------
//           - Lado bus    : cs_i, addr_i, we_i, wdata_i, rdata_o
//           - Lado planta : pwm_o          -> al driver del MOSFET (boost)
//                           pwm_trigger_o  -> al periférico ADC/XADC
//
// Mapa de registros (base = 0x0001_0100)
// --------------------------------------
//   0x0001_0100  CTRL/STATUS
//                  bit 0    : enable    (R/W)
//                  bit 2:1  : freq_sel  (R/W)  00=25k 01=50k 10=100k 11=200k
//                  bit 3    : running   (RO)
//   0x0001_0104  DUTY
//                  bit 6:0  : duty_pct  (R/W)  saturado a [0,100]
//
// Integración con el bus del sistema
// ----------------------------------
// El cs_i lo debe generar un decodificador de direcciones del bus, por
// ejemplo: cs_pwm = (DataAddress_o[31:8] == 24'h0001_01) && data_access;
// Y el rdata_o se mezcla con los demás periféricos en un OR-mux o un mux
// seleccionado por la región de dirección.
//==============================================================================
module pwm_top (
    input  logic        clk_i,
    input  logic        rst_i,

    // Interfaz de bus (slave)
    input  logic        cs_i,          // chip-select del periférico PWM
    input  logic [3:0]  addr_i,        // offset interno (0x0..0x4)
    input  logic        we_i,          // write enable
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,

    // Salidas hacia el sistema
    output logic        pwm_o,         // señal PWM al MOSFET del boost
    output logic        pwm_trigger_o  // sincronización al ADC/XADC
);

    //--------------------------------------------------------------------------
    // Conexiones internas regs <-> core
    //--------------------------------------------------------------------------
    logic        enable_w;
    logic [1:0]  freq_sel_w;
    logic [6:0]  duty_pct_w;
    logic        running_w;

    //--------------------------------------------------------------------------
    // Banco de registros (controlpath)
    //--------------------------------------------------------------------------
    pwm_regs u_pwm_regs (
        .clk_i      (clk_i),
        .rst_i      (rst_i),

        .cs_i       (cs_i),
        .addr_i     (addr_i),
        .we_i       (we_i),
        .wdata_i    (wdata_i),
        .rdata_o    (rdata_o),

        .enable_o   (enable_w),
        .freq_sel_o (freq_sel_w),
        .duty_pct_o (duty_pct_w),
        .running_i  (running_w)
    );

    //--------------------------------------------------------------------------
    // Generador PWM (datapath)
    //--------------------------------------------------------------------------
    pwm_core u_pwm_core (
        .clk_i         (clk_i),
        .rst_i         (rst_i),

        .enable_i      (enable_w),
        .freq_sel_i    (freq_sel_w),
        .duty_pct_i    (duty_pct_w),

        .pwm_o         (pwm_o),
        .pwm_trigger_o (pwm_trigger_o),
        .running_o     (running_w)
    );

endmodule