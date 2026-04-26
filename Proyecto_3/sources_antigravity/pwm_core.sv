//==============================================================================
// File   : pwm_core.sv
// Module : pwm_core
// Desc   : DATAPATH del periférico PWM. Genera la señal PWM y el pulso de
//          sincronización pwm_trigger_o para el ADC.
//
// Estrategia de generación
// ------------------------
// Se usa un esquema de DOS contadores en cascada para obtener resolución
// de exactamente 1% sin necesidad de divisores en hardware:
//
//   - sub_count : cuenta los ciclos de clk_i que dura un "1% del periodo".
//   - pct_count : cuenta de 0..99 (el porcentaje actual del periodo PWM).
//
// La salida PWM es alta cuando pct_count < duty_pct_i.
//
// Frecuencias soportadas (con clk_i = 100 MHz)
// --------------------------------------------
//   freq_sel | f_pwm   | ciclos por 1% (sub_count máx + 1)
//   ---------+---------+----------------------------------
//      00    |  25 kHz |           40
//      01    |  50 kHz |           20
//      10    | 100 kHz |           10
//      11    | 200 kHz |            5
//
// Todas cumplen el requisito f_sw > 20 kHz del proyecto y dan resolución
// de 1% en el ciclo de trabajo. Los 4 valores de freq_sel son válidos
// (el spec exige al menos 3).
//
// pwm_trigger_o
// -------------
// Pulso de UN solo ciclo de clk_i al inicio de cada periodo PWM
// (pct_count == 0 && sub_count == 0). El periférico ADC lo usa, cuando
// pwm_trig_en está activo, para arrancar la conversión sincronizada.
//
// Notas de implementación
// -----------------------
// - Si !enable_i, ambos contadores se mantienen en 0 y la salida PWM es 0,
//   garantizando un arranque limpio (siempre se inicia en periodo nuevo).
// - Si se cambia freq_sel en caliente puede haber un periodo "raro" antes
//   de estabilizarse; se recomienda configurar freq_sel sólo durante init
//   (con enable=0) y luego activar el PWM.
// - Reset síncrono.
//==============================================================================
module pwm_core (
    input  logic        clk_i,
    input  logic        rst_i,

    // Configuración desde el banco de registros (controlpath)
    input  logic        enable_i,
    input  logic [1:0]  freq_sel_i,
    input  logic [6:0]  duty_pct_i,    // ya saturado a [0,100] por pwm_regs

    // Salidas
    output logic        pwm_o,         // señal PWM hacia el driver del MOSFET
    output logic        pwm_trigger_o, // pulso de sincronización al ADC
    output logic        running_o      // estado: el generador está activo
);

    //--------------------------------------------------------------------------
    // LUT de ciclos por 1% según freq_sel  (clk_i = 100 MHz)
    //--------------------------------------------------------------------------
    logic [5:0] cycles_per_pct;        // valores: 5, 10, 20, 40 -> caben en 6b

    always_comb begin
        unique case (freq_sel_i)
            2'b00 : cycles_per_pct = 6'd40;   //  25 kHz
            2'b01 : cycles_per_pct = 6'd20;   //  50 kHz
            2'b10 : cycles_per_pct = 6'd10;   // 100 kHz
            2'b11 : cycles_per_pct = 6'd5;    // 200 kHz
            default: cycles_per_pct = 6'd40;
        endcase
    end

    //--------------------------------------------------------------------------
    // Sub-contador: cuenta ciclos dentro de un "1% del periodo"
    //--------------------------------------------------------------------------
    logic [5:0] sub_count;
    logic       sub_tick;              // pulso al fin del 1%

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            sub_count <= 6'd0;
        end
        else if (!enable_i) begin
            sub_count <= 6'd0;          // arranque limpio en periodo nuevo
        end
        else if (sub_count == cycles_per_pct - 6'd1) begin
            sub_count <= 6'd0;
        end
        else begin
            sub_count <= sub_count + 6'd1;
        end
    end

    assign sub_tick = enable_i && (sub_count == cycles_per_pct - 6'd1);

    //--------------------------------------------------------------------------
    // Contador de porcentaje: 0..99
    //--------------------------------------------------------------------------
    logic [6:0] pct_count;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            pct_count <= 7'd0;
        end
        else if (!enable_i) begin
            pct_count <= 7'd0;
        end
        else if (sub_tick) begin
            if (pct_count == 7'd99)
                pct_count <= 7'd0;     // fin de periodo
            else
                pct_count <= pct_count + 7'd1;
        end
    end

    //--------------------------------------------------------------------------
    // Generación de la señal PWM
    //   - Si duty = 0   -> pwm_o siempre 0 (porque 0 < 0 es falso)
    //   - Si duty = 100 -> pwm_o siempre 1 (porque pct_count < 100 siempre)
    //--------------------------------------------------------------------------
    assign pwm_o = enable_i && (pct_count < duty_pct_i);

    //--------------------------------------------------------------------------
    // Trigger al ADC: pulso de 1 ciclo al inicio de cada periodo PWM
    //--------------------------------------------------------------------------
    assign pwm_trigger_o = enable_i && (pct_count == 7'd0) && (sub_count == 6'd0);

    //--------------------------------------------------------------------------
    // Estado "running"
    //--------------------------------------------------------------------------
    assign running_o = enable_i;

endmodule