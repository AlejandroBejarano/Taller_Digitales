## =============================================================================
## Constraints para uart_game_top - Basys3 (xc7a35tcpg236-1)
## =============================================================================

## Reloj de sistema (100 MHz - Pin W5)
set_property PACKAGE_PIN W5 [get_ports clk_100MHz]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100MHz]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk_100MHz]

## Botones
# Reset (Botón Central - BTNC)
set_property PACKAGE_PIN U18 [get_ports rst_i]
set_property IOSTANDARD LVCMOS33 [get_ports rst_i]
# Iniciar partida/ronda (Botón Arriba - BTNU)
set_property PACKAGE_PIN T18 [get_ports btn_start_i]
set_property IOSTANDARD LVCMOS33 [get_ports btn_start_i]

## LEDs de diagnóstico
# led[0]: Transmitiendo pregunta
set_property PACKAGE_PIN U16 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
# led[1]: Esperando respuesta
set_property PACKAGE_PIN E19 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]
# led[2]: Respuesta correcta
set_property PACKAGE_PIN U19 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]
# led[3]: PLL locked
set_property PACKAGE_PIN V19 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

## UART (USB-UART del Basys3)
set_property PACKAGE_PIN A18     [get_ports tx]
set_property IOSTANDARD LVCMOS33 [get_ports tx]
set_property PACKAGE_PIN B18     [get_ports rx]
set_property IOSTANDARD LVCMOS33 [get_ports rx]

## Configuración de Bitstream
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]