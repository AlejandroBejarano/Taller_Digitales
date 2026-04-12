# =============================================================================
# Constraints para uart_prueba_3 - Basys3 (xc7a35tcpg236-1)
#
# REFERENCIA OFICIAL DIGILENT (Basys3 Master XDC):
#   RsRx (FPGA RECIBE  desde PC) = B18   <- FPGA rx input
#   RsTx (FPGA TRANSMITE hacia PC) = A18  <- FPGA tx output
#
# ATENCION: el chip FT2232H nombra sus pines desde su propia perspectiva:
#   - FT2232H "TXD" (el chip transmite) = B18 -> la FPGA RECIBE en B18 = rx
#   - FT2232H "RXD" (el chip recibe)   = A18 -> la FPGA TRANSMITE en A18 = tx
# No confundir la nomenclatura del chip USB con la de la FPGA.
# =============================================================================

# Reloj de sistema 100 MHz (Pin W5, banco 34)
set_property PACKAGE_PIN W5      [get_ports clk_100MHz]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100MHz]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk_100MHz]

# Reset - BTNC (boton central, activo alto, banco 34)
set_property PACKAGE_PIN U18     [get_ports rst_i]
set_property IOSTANDARD LVCMOS33 [get_ports rst_i]

# UART - USB-UART integrado Basys3
# A18 = RsTx : dato que SALE de la FPGA hacia el PC  (FPGA transmite)
# B18 = RsRx : dato que ENTRA a la FPGA desde el PC  (FPGA recibe)
set_property PACKAGE_PIN A18     [get_ports tx]
set_property IOSTANDARD LVCMOS33 [get_ports tx]
set_property PACKAGE_PIN B18     [get_ports rx]
set_property IOSTANDARD LVCMOS33 [get_ports rx]

# LEDs de diagnostico - todos banco 34 (VCCO=3.3V)
# LED[0] = PLL locked       -> LD0 (U16)
# LED[1] = send_pending     -> LD1 (E19)
# LED[2] = new_rx_flag      -> LD2 (V19)
# LED[3] = reset interno    -> LD3 (U15)
set_property PACKAGE_PIN U16     [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]

set_property PACKAGE_PIN E19     [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]

set_property PACKAGE_PIN V19     [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]

set_property PACKAGE_PIN U15     [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

# Timing: false path para la entrada de reset
set_false_path -from [get_ports rst_i] -to [all_registers]