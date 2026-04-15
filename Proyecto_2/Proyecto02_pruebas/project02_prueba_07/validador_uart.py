import serial
import time
import argparse # Cambio porque... necesitamos leer argumentos de la terminal

# --- Configuración de argumentos ---
parser = argparse.ArgumentParser(description='Validador UART para Proyecto Jeopardy')
parser.add_argument('--port', type=str, default='/dev/ttyUSB0', 
                    help='Ruta del puerto serial (ej: /dev/ttyUSB0 o COM3)')
args = parser.parse_args()

# Ahora PUERTO toma el valor que escribas en la terminal
PUERTO = args.port 
BAUDIOS = 115200 # El PDF exige 115200

try:
    # Abrir puerto serie
    ser = serial.Serial(PUERTO, BAUDIOS, timeout=1)
    print(f"--- Conectado exitosamente a {PUERTO} ---")
    print(f"--- Velocidad: {BAUDIOS} baudios ---")
    print("Esperando datos de la FPGA (Presiona el botón en la Basys3)...")

    while True:
        # 1. Escuchar lo que manda la FPGA
        if ser.in_waiting > 0:
            dato_recibido = ser.read()
            try:
                caracter = dato_recibido.decode('ascii')
            except:
                caracter = "Dato no ASCII"
                
            hex_val = dato_recibido.hex().upper()
            
            print(f"\n[FPGA -> PC] Recibido: '{caracter}' (Hex: 0x{hex_val})")
            
            # 2. Responder automáticamente
            # Enviamos una 'B' para confirmar que la FPGA también puede recibir
            time.sleep(0.05)  # Dale 50ms a la FPGA 
            respuesta = b'B' 
            ser.write(respuesta)
            print(f"[PC -> FPGA] Respuesta enviada: '{respuesta.decode()}'")
            
        time.sleep(0.01)

except serial.SerialException as e:
    print(f"\nERROR: No se pudo abrir el puerto {PUERTO}.")
    print(f"Causa: {e}")
    print("\nCONSEJO: Verifica que hiciste 'usbipd attach' y que tienes permisos (sudo chmod 666 {PUERTO})")
except KeyboardInterrupt:
    print("\nScript detenido por el usuario.")
    if 'ser' in locals(): ser.close()