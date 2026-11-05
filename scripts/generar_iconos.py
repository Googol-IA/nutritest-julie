"""Genera los iconos PNG de la web (192, 512 y 180 para iPhone). Uso: python scripts/generar_iconos.py"""
from pathlib import Path
from PIL import Image, ImageDraw

DESTINO = Path(__file__).resolve().parent.parent / "web" / "iconos"
VERDE, VERDE_CLARO, BLANCO = (47, 158, 91), (191, 232, 205), (255, 255, 255)


def icono(tam: int, redondeo: bool = True) -> Image.Image:
    e = 4  # superescalado para bordes suaves
    s = tam * e
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    k = s / 512
    if redondeo:
        d.rounded_rectangle([0, 0, s, s], radius=int(112 * k), fill=VERDE)
    else:
        d.rectangle([0, 0, s, s], fill=VERDE)
    # Manzana: dos lóbulos + base
    d.ellipse([110 * k, 150 * k, 280 * k, 390 * k], fill=BLANCO)
    d.ellipse([232 * k, 150 * k, 402 * k, 390 * k], fill=BLANCO)
    d.ellipse([170 * k, 260 * k, 342 * k, 400 * k], fill=BLANCO)
    # Hoja
    d.polygon([(256 * k, 150 * k), (276 * k, 95 * k), (316 * k, 70 * k), (300 * k, 120 * k)], fill=VERDE_CLARO)
    # Check
    d.line([(196 * k, 262 * k), (240 * k, 306 * k), (324 * k, 214 * k)], fill=VERDE, width=int(34 * k), joint="curve")
    for x, y in [(196, 262), (324, 214)]:
        r = 17 * k
        d.ellipse([x * k - r, y * k - r, x * k + r, y * k + r], fill=VERDE)
    return img.resize((tam, tam), Image.LANCZOS)


DESTINO.mkdir(parents=True, exist_ok=True)
icono(192).save(DESTINO / "icono-192.png")
icono(512, redondeo=False).save(DESTINO / "icono-512.png")
icono(180, redondeo=False).save(DESTINO / "icono-180.png")
print("Iconos generados en", DESTINO)
