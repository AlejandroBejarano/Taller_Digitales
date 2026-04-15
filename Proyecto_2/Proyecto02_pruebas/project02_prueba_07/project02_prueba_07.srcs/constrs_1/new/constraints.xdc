## =============================================================================
## Constraints para jeopardy_top - Basys3 (xc7a35tcpg236-1)
## =============================================================================

## Reloj de sistema (100 MHz - Pin W5)
set_property PACKAGE_PIN W5 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

## Botones
# Reset (Botón Central - BTNC)
set_property PACKAGE_PIN U18 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

# Botón OK/Start (Botón Arriba - BTNU)
set_property PACKAGE_PIN T18 [get_ports btn_ok]
set_property IOSTANDARD LVCMOS33 [get_ports btn_ok]

# Botón Selección (Botón Izquierda - BTNL)
set_property PACKAGE_PIN W19 [get_ports btn_sel]
set_property IOSTANDARD LVCMOS33 [get_ports btn_sel]

# Botón Scroll (Botón Derecha - BTNR)
set_property PACKAGE_PIN T17 [get_ports btn_scr]
set_property IOSTANDARD LVCMOS33 [get_ports btn_scr]


## UART (USB-UART del Basys3)
set_property PACKAGE_PIN A18     [get_ports tx]
set_property IOSTANDARD LVCMOS33 [get_ports tx]
set_property PACKAGE_PIN B18     [get_ports rx]
set_property IOSTANDARD LVCMOS33 [get_ports rx]


## Display 7 Segmentos
set_property PACKAGE_PIN W7 [get_ports {seg[0]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {seg[0]}]
set_property PACKAGE_PIN W6 [get_ports {seg[1]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {seg[1]}]
set_property PACKAGE_PIN U8 [get_ports {seg[2]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {seg[2]}]
set_property PACKAGE_PIN V8 [get_ports {seg[3]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {seg[3]}]
set_property PACKAGE_PIN U5 [get_ports {seg[4]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {seg[4]}]
set_property PACKAGE_PIN V5 [get_ports {seg[5]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {seg[5]}]
set_property PACKAGE_PIN U7 [get_ports {seg[6]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {seg[6]}]

set_property PACKAGE_PIN V7 [get_ports dp]							
set_property IOSTANDARD LVCMOS33 [get_ports dp]

set_property PACKAGE_PIN U2 [get_ports {an[0]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {an[0]}]
set_property PACKAGE_PIN U4 [get_ports {an[1]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {an[1]}]
set_property PACKAGE_PIN V4 [get_ports {an[2]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {an[2]}]
set_property PACKAGE_PIN W4 [get_ports {an[3]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {an[3]}]


## Buzzer en Pmod JA (Pin 1 -> J1)
set_property PACKAGE_PIN J1 [get_ports buzzer]
set_property IOSTANDARD LVCMOS33 [get_ports buzzer]


## Pmod LCD (Pmod CLP HD44780)
# Conectado a JB y JC según estándar Digilent
# JB1 -> RS
set_property PACKAGE_PIN A14 [get_ports lcd_rs]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_rs]
# JB2 -> R/W
set_property PACKAGE_PIN A16 [get_ports lcd_rw]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_rw]
# JB3 -> E
set_property PACKAGE_PIN B15 [get_ports lcd_e]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_e]

# Datos del LCD: JB7-JB10 y JC1-JC4
set_property PACKAGE_PIN A15 [get_ports {lcd_d[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[0]}]
set_property PACKAGE_PIN A17 [get_ports {lcd_d[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[1]}]
set_property PACKAGE_PIN C15 [get_ports {lcd_d[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[2]}]
set_property PACKAGE_PIN C16 [get_ports {lcd_d[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[3]}]

set_property PACKAGE_PIN K17 [get_ports {lcd_d[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[4]}]
set_property PACKAGE_PIN M18 [get_ports {lcd_d[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[5]}]
set_property PACKAGE_PIN N17 [get_ports {lcd_d[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[6]}]
set_property PACKAGE_PIN P18 [get_ports {lcd_d[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[7]}]

## Configuración de Bitstream
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]