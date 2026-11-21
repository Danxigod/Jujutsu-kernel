#!/usr/bin/env python3
"""genera un WAV de prueba con un tono distinto en cada canal.

izquierda = 440 Hz, derecha = 880 Hz. Con esto se oye si el movil esta
repartiendo los canales: en el altavoz de abajo y en el auricular de arriba
deben sonar tonos distintos.
"""
import math
import struct
import wave

RATE = 44100
SECONDS = 12
LEFT_HZ = 440.0
RIGHT_HZ = 880.0


def main(path: str) -> None:
    frames = bytearray()
    total = RATE * SECONDS
    for i in range(total):
        t = i / RATE
        # un poco de envolvente para que se note cuando cambia el canal
        env = 0.6 * (1.0 if (i // (RATE // 4)) % 2 == 0 else 0.35)
        left = env * math.sin(2 * math.pi * LEFT_HZ * t)
        right = env * math.sin(2 * math.pi * RIGHT_HZ * t)
        frames += struct.pack("<hh", int(left * 32767), int(right * 32767))

    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))
    print(f"{path}: {SECONDS}s, L={LEFT_HZ} Hz, R={RIGHT_HZ} Hz")


if __name__ == "__main__":
    main("prueba-estereo.wav")
