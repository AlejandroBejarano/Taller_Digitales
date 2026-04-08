# ==============================================================================
# RELOJ Y SISTEMA
# ==============================================================================
# Reloj principal de la Basys3 (100 MHz) - Debe entrar a un PLL para generar 16MHz
set_property -dict { PACKAGE_PIN W5   IOSTANDARD LVCMOS33 } [get_ports { clk_i }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk_i }];

# Reset del sistema (Asignado al botón central)
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports { rst_i }];

# ==============================================================================
# PMOD CLP - LCD (JB para Datos, JC para Control)
# ==============================================================================
# Bus de Datos (Pmod JB)
set_property -dict { PACKAGE_PIN A14   IOSTANDARD LVCMOS33 } [get_ports { lcd_d[0] }]; # JB1
set_property -dict { PACKAGE_PIN A16   IOSTANDARD LVCMOS33 } [get_ports { lcd_d[1] }]; # JB2
set_property -dict { PACKAGE_PIN B15   IOSTANDARD LVCMOS33 } [get_ports { lcd_d[2] }]; # JB3
set_property -dict { PACKAGE_PIN B16   IOSTANDARD LVCMOS33 } [get_ports { lcd_d[3] }]; # JB4
set_property -dict { PACKAGE_PIN A15   IOSTANDARD LVCMOS33 } [get_ports { lcd_d[4] }]; # JB7
set_property -dict { PACKAGE_PIN A17   IOSTANDARD LVCMOS33 } [get_ports { lcd_d[5] }]; # JB8
set_property -dict { PACKAGE_PIN C15   IOSTANDARD LVCMOS33 } [get_ports { lcd_d[6] }]; # JB9
set_property -dict { PACKAGE_PIN C16   IOSTANDARD LVCMOS33 } [get_ports { lcd_d[7] }]; # JB10

# Señales de Control (Pmod JC - Fila Inferior)
set_property -dict { PACKAGE_PIN L17   IOSTANDARD LVCMOS33 } [get_ports { lcd_rs }];  # JC7
set_property -dict { PACKAGE_PIN M19   IOSTANDARD LVCMOS33 } [get_ports { lcd_rw }];  # JC8
set_property -dict { PACKAGE_PIN P17   IOSTANDARD LVCMOS33 } [get_ports { lcd_e }];   # JC9

# ==============================================================================
# INTERFAZ DE JUEGO (Botones exigidos por el Proyecto)
# ==============================================================================
# BTN_SEL: Ciclo A->B->C->D [cite: 379]
set_property -dict { PACKAGE_PIN W19   IOSTANDARD LVCMOS33 } [get_ports { btn_sel }]; # Botón Izquierdo

# BTN_OK: Confirmar respuesta [cite: 380]
set_property -dict { PACKAGE_PIN T17   IOSTANDARD LVCMOS33 } [get_ports { btn_ok }];  # Botón Derecho

# BTN_SCR: Alternar Pregunta/Opciones [cite: 381]
set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports { btn_scr }]; # Botón Arriba

# ==============================================================================
# RETROALIMENTACIÓN (7 Segmentos y Buzzer)
# ==============================================================================
# Para mostrar Marcador y Tiempo Restante 
set_property -dict { PACKAGE_PIN W7   IOSTANDARD LVCMOS33 } [get_ports { seg[0] }];
set_property -dict { PACKAGE_PIN W6   IOSTANDARD LVCMOS33 } [get_ports { seg[1] }];
set_property -dict { PACKAGE_PIN U8   IOSTANDARD LVCMOS33 } [get_ports { seg[2] }];
set_property -dict { PACKAGE_PIN V8   IOSTANDARD LVCMOS33 } [get_ports { seg[3] }];
set_property -dict { PACKAGE_PIN U5   IOSTANDARD LVCMOS33 } [get_ports { seg[4] }];
set_property -dict { PACKAGE_PIN V5   IOSTANDARD LVCMOS33 } [get_ports { seg[5] }];
set_property -dict { PACKAGE_PIN U7   IOSTANDARD LVCMOS33 } [get_ports { seg[6] }];

set_property -dict { PACKAGE_PIN U2   IOSTANDARD LVCMOS33 } [get_ports { an[0] }];
set_property -dict { PACKAGE_PIN U4   IOSTANDARD LVCMOS33 } [get_ports { an[1] }];
set_property -dict { PACKAGE_PIN V4   IOSTANDARD LVCMOS33 } [get_ports { an[2] }];
set_property -dict { PACKAGE_PIN W4   IOSTANDARD LVCMOS33 } [get_ports { an[3] }];

# Buzzer (Pmod de salida opcional) [cite: 384]
# set_property -dict { PACKAGE_PIN G2   IOSTANDARD LVCMOS33 } [get_ports { buzzer }]; # Pmod JA7