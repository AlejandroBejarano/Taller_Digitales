# =============================================================================
# Constraints para peripheral_top - Basys3 (xc7a35tcpg236-1)
# Proyecto: Jeopardy FPGA
# =============================================================================

# -----------------------------------------------------------------------------
# Reloj de Sistema (100 MHz físico en W5)
# Nota: Tu módulo espera 16 MHz. Asegúrate de usar un Clock Wizard (PLL/MMCM) 
# internamente para bajar de 100 MHz a 16 MHz.
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN W5 [get_ports clk_i]							
set_property IOSTANDARD LVCMOS33 [get_ports clk_i]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk_i]

# -----------------------------------------------------------------------------
# Reset Global (Botón Central - BTNC)
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN U18 [get_ports rst_i]						
set_property IOSTANDARD LVCMOS33 [get_ports rst_i]

# -----------------------------------------------------------------------------
# UART (Comunicación con PC a través del puente USB-UART)
# -----------------------------------------------------------------------------
# FPGA recibe (RX) desde la PC
set_property PACKAGE_PIN B18 [get_ports rx]						
set_property IOSTANDARD LVCMOS33 [get_ports rx]
# FPGA transmite (TX) hacia la PC
set_property PACKAGE_PIN A18 [get_ports tx]						
set_property IOSTANDARD LVCMOS33 [get_ports tx]

# -----------------------------------------------------------------------------
# LCD PmodCLP (Datos en JB y Control en JA)
# -----------------------------------------------------------------------------
# Bus de Datos lcd_d[7:0] -> Pmod JB
set_property PACKAGE_PIN A14 [get_ports {lcd_d[0]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[0]}]
set_property PACKAGE_PIN A16 [get_ports {lcd_d[1]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[1]}]
set_property PACKAGE_PIN B15 [get_ports {lcd_d[2]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[2]}]
set_property PACKAGE_PIN B16 [get_ports {lcd_d[3]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[3]}]
set_property PACKAGE_PIN A15 [get_ports {lcd_d[4]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[4]}]
set_property PACKAGE_PIN A17 [get_ports {lcd_d[5]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[5]}]
set_property PACKAGE_PIN C15 [get_ports {lcd_d[6]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[6]}]
set_property PACKAGE_PIN C16 [get_ports {lcd_d[7]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[7]}]

# Señales de Control -> Pmod JA
set_property PACKAGE_PIN J1 [get_ports lcd_rs]						
set_property IOSTANDARD LVCMOS33 [get_ports lcd_rs]
set_property PACKAGE_PIN L2 [get_ports lcd_rw]						
set_property IOSTANDARD LVCMOS33 [get_ports lcd_rw]
set_property PACKAGE_PIN J2 [get_ports lcd_e]						
set_property IOSTANDARD LVCMOS33 [get_ports lcd_e]

# -----------------------------------------------------------------------------
# 7 Segmentos (Display de 4 dígitos)
# -----------------------------------------------------------------------------
# Cátodos (seg_o[6:0]) - Segmentos A a G
set_property PACKAGE_PIN W7 [get_ports {seg_o[0]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {seg_o[0]}]
set_property PACKAGE_PIN W6 [get_ports {seg_o[1]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {seg_o[1]}]
set_property PACKAGE_PIN U8 [get_ports {seg_o[2]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {seg_o[2]}]
set_property PACKAGE_PIN V8 [get_ports {seg_o[3]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {seg_o[3]}]
set_property PACKAGE_PIN U5 [get_ports {seg_o[4]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {seg_o[4]}]
set_property PACKAGE_PIN V5 [get_ports {seg_o[5]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {seg_o[5]}]
set_property PACKAGE_PIN U7 [get_ports {seg_o[6]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {seg_o[6]}]

# Punto Decimal
set_property PACKAGE_PIN V7 [get_ports dp_o]							
set_property IOSTANDARD LVCMOS33 [get_ports dp_o]

# Ánodos (an_o[3:0]) - Selección de Dígito (Activo Bajo)
set_property PACKAGE_PIN U2 [get_ports {an_o[0]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {an_o[0]}]
set_property PACKAGE_PIN U4 [get_ports {an_o[1]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {an_o[1]}]
set_property PACKAGE_PIN V4 [get_ports {an_o[2]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {an_o[2]}]
set_property PACKAGE_PIN W4 [get_ports {an_o[3]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {an_o[3]}]

# -----------------------------------------------------------------------------
# Buzzer (Efectos de sonido)
# Asignado a JA4 (Pin físico G2)
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN G2 [get_ports buzzer_pin]					
set_property IOSTANDARD LVCMOS33 [get_ports buzzer_pin]

# -----------------------------------------------------------------------------
# Configuraciones de Voltaje de Configuración (Recomendado para Basys3)
# -----------------------------------------------------------------------------
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]