## =============================================================================
## constraints_top.xdc
## Basys3 xc7a35tcpg236c - top_jeopardy
## =============================================================================
## ADVERTENCIA LCD: Verifica que el orden de lcd_d[7:0] en JB/JC coincide
## exactamente con tu cableado fisico del PmodCLP. Si la pantalla muestra
## caracteres incorrectos, intercambia el orden de los bits de lcd_d.
## =============================================================================

## ----------------------------------------------------------------------------
## Reloj del sistema: 100 MHz
## ----------------------------------------------------------------------------
set_property PACKAGE_PIN W5  [get_ports clk]
set_property IOSTANDARD  LVCMOS33 [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

## ----------------------------------------------------------------------------
## Botones (activo en alto en Basys3)
## BTNC=Reset  BTNU=btn_ok  BTNL=btn_sel  BTNR=btn_scr
## ----------------------------------------------------------------------------
set_property PACKAGE_PIN U18 [get_ports rst]
set_property IOSTANDARD  LVCMOS33 [get_ports rst]

set_property PACKAGE_PIN T18 [get_ports btn_ok]
set_property IOSTANDARD  LVCMOS33 [get_ports btn_ok]

set_property PACKAGE_PIN W19 [get_ports btn_sel]
set_property IOSTANDARD  LVCMOS33 [get_ports btn_sel]

set_property PACKAGE_PIN T17 [get_ports btn_scr]
set_property IOSTANDARD  LVCMOS33 [get_ports btn_scr]

## ----------------------------------------------------------------------------
## Switches SW[3:0] para semilla del LFSR
## (Descomentar si se agrega input sw[3:0] a top_jeopardy)
## ----------------------------------------------------------------------------
#set_property PACKAGE_PIN V17 [get_ports {sw[0]}]
#set_property IOSTANDARD  LVCMOS33 [get_ports {sw[0]}]
#set_property PACKAGE_PIN V16 [get_ports {sw[1]}]
#set_property IOSTANDARD  LVCMOS33 [get_ports {sw[1]}]
#set_property PACKAGE_PIN W16 [get_ports {sw[2]}]
#set_property IOSTANDARD  LVCMOS33 [get_ports {sw[2]}]
#set_property PACKAGE_PIN W17 [get_ports {sw[3]}]
#set_property IOSTANDARD  LVCMOS33 [get_ports {sw[3]}]

## ----------------------------------------------------------------------------
## UART (USB-UART integrado en Basys3)
## ----------------------------------------------------------------------------
set_property PACKAGE_PIN B18 [get_ports rx]
set_property IOSTANDARD  LVCMOS33 [get_ports rx]

set_property PACKAGE_PIN A18 [get_ports tx]
set_property IOSTANDARD  LVCMOS33 [get_ports tx]

## ----------------------------------------------------------------------------
## Display de 7 segmentos (catodo comun, activo bajo)
## seg_o[0]=CA  [1]=CB  [2]=CC  [3]=CD  [4]=CE  [5]=CF  [6]=CG
## ----------------------------------------------------------------------------
set_property PACKAGE_PIN W7  [get_ports {seg_o[0]}]
set_property PACKAGE_PIN W6  [get_ports {seg_o[1]}]
set_property PACKAGE_PIN U8  [get_ports {seg_o[2]}]
set_property PACKAGE_PIN V8  [get_ports {seg_o[3]}]
set_property PACKAGE_PIN U5  [get_ports {seg_o[4]}]
set_property PACKAGE_PIN V5  [get_ports {seg_o[5]}]
set_property PACKAGE_PIN U7  [get_ports {seg_o[6]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {seg_o[*]}]

set_property PACKAGE_PIN V7  [get_ports dp_o]
set_property IOSTANDARD  LVCMOS33 [get_ports dp_o]

set_property PACKAGE_PIN U2  [get_ports {an_o[0]}]
set_property PACKAGE_PIN U4  [get_ports {an_o[1]}]
set_property PACKAGE_PIN V4  [get_ports {an_o[2]}]
set_property PACKAGE_PIN W4  [get_ports {an_o[3]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {an_o[*]}]

## ----------------------------------------------------------------------------
## PMOD JA - Buzzer (pin 1 = JA1)
## ----------------------------------------------------------------------------
set_property PACKAGE_PIN J1  [get_ports buzzer_pin]
set_property IOSTANDARD  LVCMOS33 [get_ports buzzer_pin]

## ----------------------------------------------------------------------------
## PMOD JB - LCD control + datos D[7:4]
## JB1=lcd_rs  JB2=lcd_rw  JB3=lcd_e
## JB4=lcd_d[4]  JB7=lcd_d[5]  JB8=lcd_d[6]  JB9=lcd_d[7]
## ----------------------------------------------------------------------------
set_property PACKAGE_PIN A14 [get_ports lcd_rs]
set_property IOSTANDARD  LVCMOS33 [get_ports lcd_rs]

set_property PACKAGE_PIN A16 [get_ports lcd_rw]
set_property IOSTANDARD  LVCMOS33 [get_ports lcd_rw]

set_property PACKAGE_PIN B15 [get_ports lcd_e]
set_property IOSTANDARD  LVCMOS33 [get_ports lcd_e]

set_property PACKAGE_PIN B16 [get_ports {lcd_d[4]}]
set_property PACKAGE_PIN A15 [get_ports {lcd_d[5]}]
set_property PACKAGE_PIN A17 [get_ports {lcd_d[6]}]
set_property PACKAGE_PIN C15 [get_ports {lcd_d[7]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {lcd_d[*]}]

## ----------------------------------------------------------------------------
## PMOD JC - LCD datos D[3:0]
## JC1=lcd_d[3]  JC2=lcd_d[2]  JC3=lcd_d[1]  JC4=lcd_d[0]
## ----------------------------------------------------------------------------
set_property PACKAGE_PIN K17 [get_ports {lcd_d[3]}]
set_property PACKAGE_PIN M18 [get_ports {lcd_d[2]}]
set_property PACKAGE_PIN N17 [get_ports {lcd_d[1]}]
set_property PACKAGE_PIN P18 [get_ports {lcd_d[0]}]

## ----------------------------------------------------------------------------
## Configuracion global de la FPGA
## ----------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
