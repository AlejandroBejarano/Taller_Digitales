#!/usr/bin/env python3
"""
uart_prueba_3.py
Prueba de comunicacion UART FPGA <-> PC

Uso:
  python uart_prueba_3.py --port COM3
  python uart_prueba_3.py --port COM3 --interactive
  python uart_prueba_3.py --port COM3 --skip-auto
"""

import argparse
import sys
import time
import serial

DEFAULT_BAUD    = 115_200
DEFAULT_TIMEOUT = 5.0

GREEN  = "\033[92m"
RED    = "\033[91m"
YELLOW = "\033[93m"
CYAN   = "\033[96m"
RESET  = "\033[0m"

def ok(msg):   return f"{GREEN}[PASS]{RESET} {msg}"
def err(msg):  return f"{RED}[FAIL]{RESET} {msg}"
def info(msg): return f"{CYAN}[INFO]{RESET} {msg}"
def warn(msg): return f"{YELLOW}[WARN]{RESET} {msg}"

def open_port(port, baud):
    try:
        ser = serial.Serial(
            port=port, baudrate=baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=DEFAULT_TIMEOUT,
        )
        print(info(f"Puerto {port} abierto a {baud} baud."))
        return ser
    except serial.SerialException as e:
        print(err(f"No se pudo abrir {port}: {e}"))
        sys.exit(1)

def send_byte(ser, byte_val):
    ser.write(bytes([byte_val]))
    ser.flush()

def receive_byte(ser, timeout=None):
    old = ser.timeout
    if timeout is not None:
        ser.timeout = timeout
    data = ser.read(1)
    ser.timeout = old
    return data[0] if data else None

# =============================================================================
# TEST 1: TX automatico (0x55 = 'U')
# El script abre el puerto y luego avisa al usuario que presione RESET.
# Asi nos aseguramos de estar escuchando antes de que la FPGA envie el byte.
# =============================================================================
def test_tx_automatico(ser):
    ser.reset_input_buffer()
    print()
    print(warn(">>> Presiona ahora el boton BTNC (reset) de la Basys3 <<<"))
    print(info("Esperando byte 0x55 ('U') de la FPGA (timeout 10 s)..."))

    byte_rx = receive_byte(ser, timeout=10.0)

    if byte_rx is None:
        print(err("TEST 1 - Timeout: no se recibio ningun byte de la FPGA."))
        return False
    if byte_rx == 0x55:
        print(ok(f"TEST 1 - Recibido 0x{byte_rx:02X} ('{chr(byte_rx)}') correcto."))
        return True
    else:
        char = chr(byte_rx) if 32 <= byte_rx < 127 else '?'
        print(err(f"TEST 1 - Esperado 0x55, recibido 0x{byte_rx:02X} ('{char}')"))
        return False

# =============================================================================
# TEST 2: Eco byte fijo 0xA5
# =============================================================================
def test_eco_fijo(ser):
    byte_tx = 0xA5
    print(info(f"TEST 2 - Enviando 0x{byte_tx:02X} y esperando eco..."))
    ser.reset_input_buffer()
    send_byte(ser, byte_tx)

    byte_rx = receive_byte(ser)
    if byte_rx is None:
        print(err("TEST 2 - Timeout: la FPGA no respondio."))
        return False
    if byte_rx == byte_tx:
        print(ok(f"TEST 2 - Eco correcto: 0x{byte_rx:02X}"))
        return True
    else:
        print(err(f"TEST 2 - Enviado 0x{byte_tx:02X}, recibido 0x{byte_rx:02X}"))
        return False

# =============================================================================
# TEST 3: Eco secuencia A, B, C, D
# =============================================================================
def test_eco_secuencia(ser):
    chars = [ord('A'), ord('B'), ord('C'), ord('D')]
    all_ok = True
    print(info("TEST 3 - Enviando secuencia A/B/C/D y verificando ecos..."))

    for c in chars:
        ser.reset_input_buffer()
        send_byte(ser, c)
        time.sleep(0.1)
        byte_rx = receive_byte(ser)

        if byte_rx is None:
            print(err(f"  '{chr(c)}' (0x{c:02X}) -> Timeout sin eco"))
            all_ok = False
        elif byte_rx == c:
            print(ok(f"  '{chr(c)}' (0x{c:02X}) -> Eco OK"))
        else:
            char = chr(byte_rx) if 32 <= byte_rx < 127 else '?'
            print(err(f"  '{chr(c)}' (0x{c:02X}) -> Eco inesperado 0x{byte_rx:02X} ('{char}')"))
            all_ok = False
        time.sleep(0.2)

    return all_ok

# =============================================================================
# Modo interactivo
# =============================================================================
def modo_interactivo(ser):
    print()
    print(info("Modo interactivo. Escribe un caracter y Enter para enviarlo."))
    print(info("Escribe 'q' + Enter para salir."))
    print()

    while True:
        try:
            entrada = input("  Enviar > ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break

        if not entrada:
            continue
        if entrada.lower() == 'q':
            break

        byte_tx = ord(entrada[0]) & 0xFF
        send_byte(ser, byte_tx)
        print(f"  -> Enviado: 0x{byte_tx:02X} ('{entrada[0]}')")

        byte_rx = receive_byte(ser)
        if byte_rx is None:
            print(warn("  <- Timeout: no se recibio eco."))
        elif byte_rx == byte_tx:
            char = chr(byte_rx) if 32 <= byte_rx < 127 else '?'
            print(ok(f"  <- Eco: 0x{byte_rx:02X} ('{char}')"))
        else:
            char = chr(byte_rx) if 32 <= byte_rx < 127 else '?'
            print(err(f"  <- Eco inesperado: 0x{byte_rx:02X} ('{char}')"))
        print()

# =============================================================================
# Main
# =============================================================================
def main():
    parser = argparse.ArgumentParser(
        description="Prueba UART FPGA <-> PC (uart_prueba_3)"
    )
    parser.add_argument("--port", "-p", default="/dev/ttyUSB0",
                        help="Puerto serie (ej: COM3, /dev/ttyUSB0)")
    parser.add_argument("--baud", "-b", type=int, default=DEFAULT_BAUD)
    parser.add_argument("--skip-auto", "-s", action="store_true",
                        help="Omite TEST 1 (TX automatico)")
    parser.add_argument("--interactive", "-i", action="store_true",
                        help="Activa modo interactivo al final")
    args = parser.parse_args()

    print()
    print("=" * 60)
    print("  uart_prueba_3 - Verificacion UART FPGA <-> PC")
    print("=" * 60)

    ser = open_port(args.port, args.baud)
    results = {}

    try:
        if not args.skip_auto:
            results["TEST 1 TX automatico"] = test_tx_automatico(ser)
            time.sleep(0.5)
        else:
            print(warn("TEST 1 omitido (--skip-auto)"))

        results["TEST 2 Eco fijo 0xA5"]  = test_eco_fijo(ser)
        time.sleep(0.3)

        results["TEST 3 Eco secuencia"]  = test_eco_secuencia(ser)
        time.sleep(0.3)

        print()
        print("=" * 60)
        print("  RESUMEN DE TESTS")
        print("=" * 60)
        passed = 0
        for name, result in results.items():
            print(f"  {ok(name) if result else err(name)}")
            if result:
                passed += 1
        print(f"\n  Total: {passed}/{len(results)} tests pasaron.")
        print()

        if args.interactive:
            modo_interactivo(ser)

    except KeyboardInterrupt:
        print(warn("\nInterrumpido por el usuario."))
    finally:
        ser.close()
        print(info(f"Puerto {args.port} cerrado."))

if __name__ == "__main__":
    main()