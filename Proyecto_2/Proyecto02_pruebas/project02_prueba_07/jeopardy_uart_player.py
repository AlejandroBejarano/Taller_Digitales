#!/usr/bin/env python3
"""
jeopardy_uart_player.py — Aplicación del Jugador PC para Jeopardy vía UART

Protocolo de comunicación (FPGA → PC):
  0x01 (SOH) + question_idx + 32 bytes pregunta
  0x02 (STX) + 32 bytes opciones (A,C,B,D × 8 bytes)
  0x03 (ETX) → PC puede enviar respuesta (A/B/C/D)
  0x05 (ENQ) + resultado (0x01=correcto, 0x00=incorrecto)
  0x06 (ACK) + score_pc + score_fpga
  0x04 (EOT) → Fin de partida

Protocolo de comunicación (PC → FPGA):
  1 byte ASCII: 'A', 'B', 'C' o 'D'

Uso:
  python jeopardy_uart_player.py --port /dev/ttyUSB0
  python jeopardy_uart_player.py --port COM3
"""

import argparse
import sys
import time
import threading
import os

try:
    import serial
except ImportError:
    print("ERROR: Necesitas instalar pyserial: pip install pyserial")
    sys.exit(1)

# =============================================================================
# Constantes de protocolo
# =============================================================================
SOH = 0x01  # Start of Header (inicio pregunta)
STX = 0x02  # Start of Text (inicio opciones)
ETX = 0x03  # End of Text (fin, PC puede responder)
EOT = 0x04  # End of Transmission (fin de partida)
ENQ = 0x05  # Enquiry (resultado de ronda)
ACK = 0x06  # Acknowledge (score update)

# =============================================================================
# Colores ANSI para la terminal
# =============================================================================
BOLD    = "\033[1m"
GREEN   = "\033[92m"
RED     = "\033[91m"
YELLOW  = "\033[93m"
CYAN    = "\033[96m"
MAGENTA = "\033[95m"
WHITE   = "\033[97m"
RESET   = "\033[0m"
BG_BLUE = "\033[44m"
BG_GREEN = "\033[42m"
BG_RED   = "\033[41m"

import wave
import struct
import math
import subprocess
import tempfile

# =============================================================================
# Generación de Sonidos y Melodías (10 Segundos y Asíncrono)
# =============================================================================
def _generate_wav(frequencies, durations, filename):
    """Genera un archivo WAV a partir de frecuencias y duraciones."""
    sample_rate = 44100
    with wave.open(filename, 'w') as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        
        # Guardaremos todos los samples en un buffer para escribirlos de una vez
        samples = []
        phase = 0.0
        for freq, duration in zip(frequencies, durations):
            num_samples = int(duration * sample_rate)
            for _ in range(num_samples):
                phase += 2.0 * math.pi * freq / sample_rate
                # Onda cuadrada simple (estilo 8-bits retro)
                val = 15000 if math.sin(phase) > 0 else -15000
                samples.append(struct.pack('<h', val))
        wav_file.writeframes(b''.join(samples))

def _play_melody_async(is_win):
    """Reproduce en un hilo separado un sonido WAV generado al vuelo por 10s."""
    def worker():
        freqs = []
        durs  = []
        
        if is_win:
            # 10 Segundos de victoria: Arpegio ascendente repetitivo rápido
            # 4 notas * 0.1s = 0.4s por ciclo. Repetimos 25 veces = 10 segundos.
            seq_f = [523.25, 659.25, 783.99, 1046.50]  # C5, E5, G5, C6
            seq_d = [0.1, 0.1, 0.1, 0.1]
            freqs = seq_f * 25
            durs  = seq_d * 25
        else:
            # 10 Segundos de error/derrota: Tonos descendentes disonantes
            # 5 notas * 0.4s = 2.0s por ciclo. Repetimos 5 veces = 10 segundos.
            seq_f = [200.0, 180.0, 160.0, 140.0, 120.0]
            seq_d = [0.4, 0.4, 0.4, 0.4, 0.4]
            freqs = seq_f * 5
            durs  = seq_d * 5
            
        # Crear un archivo temporal
        tmp_wav = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        tmp_wav.close()
        
        try:
            _generate_wav(freqs, durs, tmp_wav.name)
            
            # Reproducir el WAV con las herramientas nativas del SO
            if sys.platform == "linux":
                subprocess.run(["aplay", "-q", tmp_wav.name])
            elif sys.platform == "darwin":
                subprocess.run(["afplay", tmp_wav.name])
            else:
                import winsound
                winsound.PlaySound(tmp_wav.name, winsound.SND_FILENAME)
        except Exception as e:
            pass
        finally:
            if os.path.exists(tmp_wav.name):
                os.remove(tmp_wav.name)

    # Iniciar el hilo en segundo plano (daemon=True para cerrarlo si sale el script)
    threading.Thread(target=worker, daemon=True).start()

def play_correct_sound():
    _play_melody_async(is_win=True)

def play_incorrect_sound():
    _play_melody_async(is_win=False)

# =============================================================================
# Funciones de display
# =============================================================================
def clear_screen():
    os.system('cls' if os.name == 'nt' else 'clear')

def print_header():
    print(f"\n{BG_BLUE}{BOLD}{WHITE}")
    print("  ╔══════════════════════════════════════════════╗  ")
    print("  ║          🎮  JEOPARDY!  UART  🎮            ║  ")
    print("  ║            Jugador PC (UART)                 ║  ")
    print("  ╚══════════════════════════════════════════════╝  ")
    print(f"{RESET}")

def print_scoreboard(score_pc, score_fpga, round_num):
    print(f"\n{BOLD}{'─' * 50}{RESET}")
    print(f"  {CYAN}Ronda: {round_num}/7{RESET}   "
          f"{GREEN}PC: {score_pc}{RESET}  │  "
          f"{YELLOW}FPGA: {score_fpga}{RESET}")
    print(f"{BOLD}{'─' * 50}{RESET}")

def print_question(q_idx, question_text):
    print(f"\n  {BOLD}{MAGENTA}📝 Pregunta #{q_idx + 1}:{RESET}")
    print(f"     {BOLD}{WHITE}{question_text}{RESET}")

def print_options(options_text):
    """Parsea y muestra las 4 opciones de respuesta."""
    # Las opciones vienen como 32 bytes: A(8) + C(8) + B(8) + D(8)
    # Orden en memoria: A, C, B, D
    if len(options_text) >= 32:
        opt_a = options_text[0:8].strip()
        opt_c = options_text[8:16].strip()
        opt_b = options_text[16:24].strip()
        opt_d = options_text[24:32].strip()
    else:
        # Fallback si los datos son más cortos
        opt_a = opt_b = opt_c = opt_d = "?"
        parts = options_text.strip()
        if len(parts) > 0:
            opt_a = parts

    print(f"\n  {CYAN}┌────────────────────────────────┐{RESET}")
    print(f"  {CYAN}│{RESET}  {BOLD}A){RESET} {opt_a:<12}  {BOLD}B){RESET} {opt_b:<12}{CYAN}│{RESET}")
    print(f"  {CYAN}│{RESET}  {BOLD}C){RESET} {opt_c:<12}  {BOLD}D){RESET} {opt_d:<12}{CYAN}│{RESET}")
    print(f"  {CYAN}└────────────────────────────────┘{RESET}")

def print_result(correct):
    if correct:
        print(f"\n  {BG_GREEN}{BOLD}{WHITE} ✓ ¡RESPUESTA CORRECTA! {RESET}")
        play_correct_sound()
    else:
        print(f"\n  {BG_RED}{BOLD}{WHITE} ✗ RESPUESTA INCORRECTA {RESET}")
        play_incorrect_sound()

def print_game_over(score_pc, score_fpga):
    print(f"\n\n{BG_BLUE}{BOLD}{WHITE}")
    print("  ╔══════════════════════════════════════════════╗  ")
    print("  ║              🏆 FIN DE PARTIDA 🏆            ║  ")
    print(f"  ║    PC: {score_pc}  │  FPGA: {score_fpga}                        ║  ")
    if score_pc > score_fpga:
        print("  ║         🎉 ¡GANASTE! (Jugador PC) 🎉        ║  ")
    elif score_fpga > score_pc:
        print("  ║       😞 Ganó el Jugador FPGA 😞             ║  ")
    else:
        print("  ║            🤝 ¡EMPATE! 🤝                    ║  ")
    print("  ╚══════════════════════════════════════════════╝  ")
    print(f"{RESET}\n")

# =============================================================================
# Leer N bytes del puerto serial con timeout
# =============================================================================
def read_bytes(ser, count, timeout=10.0):
    """Lee exactamente 'count' bytes del puerto serial."""
    data = b''
    start = time.time()
    while len(data) < count and (time.time() - start) < timeout:
        remaining = count - len(data)
        chunk = ser.read(remaining)
        if chunk:
            data += chunk
    return data

# =============================================================================
# Bucle principal del juego
# =============================================================================
def game_loop(ser):
    score_pc = 0
    score_fpga = 0
    round_num = 0

    clear_screen()
    print_header()
    print(f"\n  {CYAN}[INFO]{RESET} Conectado. Esperando pregunta de la FPGA...")
    print(f"  {YELLOW}[TIP]{RESET}  Presiona el botón START en la Basys3 para iniciar.\n")

    while True:
        try:
            # Esperar un byte de control
            header = ser.read(1)
            if not header:
                continue

            cmd = header[0]

            # =================================================================
            # SOH (0x01): Inicio de pregunta
            # =================================================================
            if cmd == SOH:
                round_num += 1

                # Leer índice de pregunta (1 byte)
                idx_data = read_bytes(ser, 1)
                if len(idx_data) < 1:
                    print(f"  {RED}[ERROR]{RESET} Timeout leyendo índice de pregunta")
                    continue
                q_idx = idx_data[0]

                # Leer 32 bytes de pregunta
                q_data = read_bytes(ser, 32)
                if len(q_data) < 32:
                    print(f"  {RED}[ERROR]{RESET} Timeout leyendo pregunta (recibidos {len(q_data)} bytes)")
                    continue

                question_text = q_data.decode('ascii', errors='replace').strip()
                print_scoreboard(score_pc, score_fpga, round_num)
                print_question(q_idx, question_text)

            # =================================================================
            # STX (0x02): Inicio de opciones
            # =================================================================
            elif cmd == STX:
                # Leer 32 bytes de opciones
                a_data = read_bytes(ser, 32)
                if len(a_data) < 32:
                    print(f"  {RED}[ERROR]{RESET} Timeout leyendo opciones (recibidos {len(a_data)} bytes)")
                    continue

                options_text = a_data.decode('ascii', errors='replace')
                print_options(options_text)

            # =================================================================
            # ETX (0x03): Fin de pregunta, PC puede responder
            # =================================================================
            elif cmd == ETX:
                # Pedir respuesta al usuario
                while True:
                    try:
                        resp = input(f"\n  {BOLD}➤ Tu respuesta (A/B/C/D): {RESET}").strip().upper()
                        if resp in ('A', 'B', 'C', 'D'):
                            break
                        else:
                            print(f"  {YELLOW}[!]{RESET} Entrada inválida. Ingresa A, B, C o D.")
                    except EOFError:
                        return

                # Enviar respuesta como un solo byte ASCII
                ser.write(resp.encode('ascii'))
                ser.flush()
                print(f"  {CYAN}[ENVIADO]{RESET} Respuesta: '{resp}' (0x{ord(resp):02X})")

            # =================================================================
            # ENQ (0x05): Resultado de ronda
            # =================================================================
            elif cmd == ENQ:
                result_data = read_bytes(ser, 1)
                if len(result_data) < 1:
                    print(f"  {RED}[ERROR]{RESET} Timeout leyendo resultado")
                    continue

                correct = (result_data[0] == 0x01)
                print_result(correct)

            # =================================================================
            # ACK (0x06): Score update
            # =================================================================
            elif cmd == ACK:
                score_data = read_bytes(ser, 2)
                if len(score_data) < 2:
                    print(f"  {RED}[ERROR]{RESET} Timeout leyendo score")
                    continue

                score_pc = score_data[0]
                score_fpga = score_data[1]
                print(f"\n  {CYAN}[SCORE]{RESET} PC: {score_pc} │ FPGA: {score_fpga}")

            # =================================================================
            # EOT (0x04): Fin de partida
            # =================================================================
            elif cmd == EOT:
                print_game_over(score_pc, score_fpga)
                # Resetear para nueva partida
                score_pc = 0
                score_fpga = 0
                round_num = 0
                print(f"  {CYAN}[INFO]{RESET} Esperando nueva partida...")
                print(f"  {YELLOW}[TIP]{RESET}  Presiona START en la Basys3.\n")

            else:
                # Byte desconocido - ignorar
                pass

        except serial.SerialException as e:
            print(f"\n  {RED}[ERROR]{RESET} Error de comunicación: {e}")
            break
        except KeyboardInterrupt:
            break

# =============================================================================
# Main
# =============================================================================
def main():
    parser = argparse.ArgumentParser(
        description="Jeopardy! UART Player — Consola del jugador PC"
    )
    parser.add_argument("--port", "-p", default="/dev/ttyUSB0",
                        help="Puerto serie (ej: COM3, /dev/ttyUSB0)")
    parser.add_argument("--baud", "-b", type=int, default=115200,
                        help="Baud rate (default: 115200)")
    args = parser.parse_args()

    print_header()
    print(f"  {CYAN}[INFO]{RESET} Abriendo puerto {args.port} a {args.baud} baudios...")

    try:
        ser = serial.Serial(
            port=args.port,
            baudrate=args.baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=1.0
        )
        print(f"  {GREEN}[OK]{RESET}   Puerto abierto exitosamente.\n")

        game_loop(ser)

    except serial.SerialException as e:
        print(f"\n  {RED}[ERROR]{RESET} No se pudo abrir {args.port}: {e}")
        print(f"  {YELLOW}[TIP]{RESET}   Verifica el puerto y permisos (sudo chmod 666 {args.port})")
        sys.exit(1)

    except KeyboardInterrupt:
        pass

    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()
            print(f"\n  {CYAN}[INFO]{RESET} Puerto {args.port} cerrado. ¡Hasta luego!")

if __name__ == "__main__":
    main()
