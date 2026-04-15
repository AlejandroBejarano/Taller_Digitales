#!/usr/bin/env python3
"""
jeopardy_player.py
Consola interactiva para el jugador de Jeopardy vía UART
"""

import serial
import argparse
import sys

def main():
    parser = argparse.ArgumentParser(description="Consola de Jugador Jeopardy - FPGA")
    parser.add_argument("--port", "-p", default="/dev/ttyUSB0", help="Puerto serie (ej: COM3, /dev/ttyUSB0)")
    parser.add_argument("--baud", "-b", type=int, default=115200, help="Baud rate (default: 115200)")
    args = parser.parse_args()

    print("=" * 60)
    print(" 🎮 CONSOLA DE JUGADOR JEOPARDY INICIADA 🎮")
    print("=" * 60)

    try:
        # Configuramos timeout=None para que se quede esperando indefinidamente
        ser = serial.Serial(args.port, args.baud, timeout=None)
        print(f"[INFO] Conectado a {args.port} a {args.baud} baudios.")
        print("[INFO] Presiona el Botón de ARRIBA en tu Basys3 para pedir una pregunta...")
        print("-" * 60)

        while True:
            # 1. Esperar hasta recibir el caracter de nueva línea '\n'
            # (El hardware envía \r\n al final de la pregunta)
            incoming_bytes = ser.read_until(b'\n')
            
            # Decodificar los bytes a string (ignorando errores raros si hay ruido)
            pregunta = incoming_bytes.decode('ascii', errors='ignore').strip()
            
            if pregunta:
                print(f"\n[FPGA Pregunta]: {pregunta}")
                
                # 2. Pedir al usuario que ingrese su respuesta en la PC
                respuesta = ""
                while len(respuesta) != 1:
                    respuesta = input("Ingresa tu respuesta (A, B, C, D): ").strip().upper()
                    if len(respuesta) != 1:
                        print("Por favor, ingresa solo UNA letra.")
                
                # 3. Enviar el byte de respuesta a la FPGA
                byte_a_enviar = respuesta.encode('ascii')
                ser.write(byte_a_enviar)
                ser.flush()
                
                print(f"[PC Envía]: '{respuesta}' (0x{byte_a_enviar.hex().upper()})")
                print("Observa los LEDs en tu placa Basys3. ¡Presiona el botón para jugar de nuevo!")

    except serial.SerialException as e:
        print(f"\n[ERROR] No se pudo abrir {args.port}: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n\n[INFO] Juego terminado por el usuario. Cerrando puerto...")
        if 'ser' in locals():
            ser.close()

if __name__ == "__main__":
    main()