# Reloj de sistema (100 MHz)
set_property PACKAGE_PIN E3 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

# Reset (botón)
set_property PACKAGE_PIN D9 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

# TX/RX USB (Basys 3 integrado)
set_property PACKAGE_PIN A18 [get_ports rx]
set_property IOSTANDARD LVCMOS33 [get_ports rx]
set_property PACKAGE_PIN B18 [get_ports tx]
set_property IOSTANDARD LVCMOS33 [get_ports tx]