#!/usr/bin/env python3
"""scripts/gen-favicons.py — genera favicon.png e favicon.ico desde el mismo
diseño del favicon.svg (Saturno con anillo), sin dependencias (zlib+struct).

El render es analítico con supermuestreo 4x4 (antialiasing): planeta con
degradado, anillo elíptico inclinado cuya mitad trasera queda oculta por el
planeta. Salida: favicon.png (64x64 RGBA) y favicon.ico (16+32+48 embebidos
como PNG, formato ICO-Vista).

Uso:  python3 scripts/gen-favicons.py
"""
import math
import struct
import zlib
from pathlib import Path

SS = 4  # supermuestreo: SS x SS muestras por píxel de salida

# Diseño, en un lienzo normalizado cuyo centro es (0,0) y cuyo lado mide 1
# (sample() resta 0.5 a cada eje). El centro del anillo y del planeta caen en
# el origen; el planeta se desplaza un poco hacia arriba dentro del anillo.
PCY = -0.0375           # centro del planeta (ligeramente arriba del anillo)
R = 0.260               # radio del planeta
A, B = 0.422, 0.134     # semiejes del anillo
TH = 0.075              # grosor (media banda) del anillo
ROT = math.radians(-18)  # inclinación del anillo

RING = (0.816, 0.847, 0.918)  # #cfd8ea


def planet_color(u, v):
    """Color del planeta en coords. normalizadas (u,v) respecto al radio."""
    d = math.hypot(u, v)
    # degradado: luz arriba-izquierda, oscuro abajo-derecha (limb darkening)
    lum = 1.0 - 0.55 * min(1.0, (0.55 * u + 0.62 * v + 0.9)) / 1.9
    lum *= 1.0 - 0.35 * max(0.0, d - 0.55) / 0.45
    r = 0.99 * lum + 0.10
    g = 0.72 * lum + 0.06
    b = 0.34 * lum + 0.02
    return min(1.0, r), min(1.0, g), min(1.0, b)


def sample(fx, fy, size):
    """Color (r,g,b,a) en [0,1] de un punto del lienzo escalado a size."""
    x, y = fx / size - 0.5, fy / size - 0.5
    # planeta (origen = centro del lienzo; el anillo también se centra en 0,0)
    u, v = x / R, (y - PCY) / R
    disc = math.hypot(u, v) < 1.0
    # anillo: rotar y evaluar la banda elíptica
    ca, sa = math.cos(-ROT), math.sin(-ROT)
    rx, ry = x * ca - y * sa, x * sa + y * ca
    e = math.hypot(rx / A, ry / B)
    in_ring = 1.0 - TH < e < 1.0 + TH
    front = ry > 0.0  # mitad inferior del anillo = por delante del planeta

    if in_ring and (front or not disc):
        k = 0.75 + 0.25 * (1.0 - min(1.0, abs(e - 1.0) / TH))  # brillo del filo
        return RING[0] * k, RING[1] * k, RING[2] * k, 0.95
    if disc:
        r, g, b = planet_color(u, v)
        return r, g, b, 1.0
    return 0.0, 0.0, 0.0, 0.0


def render(size):
    w = size * SS
    out = bytearray()
    for py in range(size):  # filas, de arriba abajo (orden PNG)
        row = bytearray(b"\x00")  # filtro 0
        for px in range(size):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(SS):
                for sx in range(SS):
                    s = sample(px * SS + sx + 0.5, py * SS + sy + 0.5, w)
                    for i in range(4):
                        acc[i] += s[i]
            n = SS * SS
            row += bytes(int(acc[i] / n * 255 + 0.5) for i in range(4))
        out += row
    return bytes(out)


def png_bytes(size):
    raw = render(size)

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)  # RGBA
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def ico_bytes(pngs):
    """ICO-Vista: cabecera + entradas, cada una con un PNG embebido."""
    head = struct.pack("<HHH", 0, 1, len(pngs))
    entries = b""
    blobs = b""
    off = 6 + 16 * len(pngs)
    for size, blob in pngs:
        entries += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0,
                               1, 32, len(blob), off)
        blobs += blob
        off += len(blob)
    return head + entries + blobs


def main():
    root = Path(__file__).resolve().parent.parent
    big = png_bytes(64)
    (root / "favicon.png").write_bytes(big)
    ico = ico_bytes([(s, png_bytes(s)) for s in (16, 32, 48)])
    (root / "favicon.ico").write_bytes(ico)
    print(f"favicon.png {len(big)} B · favicon.ico {len(ico)} B")


if __name__ == "__main__":
    main()
