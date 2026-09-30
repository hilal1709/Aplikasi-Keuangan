"""Membuat animasi Lottie (bodymovin v5) untuk Aura, tanpa aset pihak ketiga."""
import json
import math
import os
import sys

OUT = sys.argv[1]
FPS = 60

EASE_OUT = ({"x": [0.33], "y": [1]}, {"x": [0.68], "y": [1]})
EASE_IN = ({"x": [0.32], "y": [0]}, {"x": [0.67], "y": [0]})
EASE_IO = ({"x": [0.65], "y": [0]}, {"x": [0.35], "y": [1]})
BACK = ({"x": [0.34], "y": [1.56]}, {"x": [0.64], "y": [1]})


def kf(frames):
    """frames: [(t, value, ease|None)] -> properti teranimasi."""
    out = []
    for i, (t, v, ease) in enumerate(frames):
        k = {"t": t, "s": v if isinstance(v, list) else [v]}
        if i < len(frames) - 1:
            o, inn = ease or EASE_IO
            k["o"], k["i"] = o, inn
        out.append(k)
    return {"a": 1, "k": out}


def static(v):
    return {"a": 0, "k": v}


def tr():
    return {"ty": "tr", "p": static([0, 0]), "a": static([0, 0]), "s": static([100, 100]),
            "r": static(0), "o": static(100), "sk": static(0), "sa": static(0), "nm": "Transform"}


def ellipse(size):
    return {"ty": "el", "d": 1, "s": static([size, size]), "p": static([0, 0]), "nm": "Ellipse"}


def fill(rgb):
    return {"ty": "fl", "c": static(rgb + [1]), "o": static(100), "r": 1, "nm": "Fill"}


def stroke(rgb, w):
    return {"ty": "st", "c": static(rgb + [1]), "o": static(100), "w": static(w), "lc": 2, "lj": 2, "nm": "Stroke"}


def path(points):
    n = len(points)
    return {"ty": "sh", "nm": "Path", "ks": static({"i": [[0, 0]] * n, "o": [[0, 0]] * n, "v": points, "c": False})}


def trim(end):
    return {"ty": "tm", "s": static(0), "e": end, "o": static(0), "m": 1, "nm": "Trim"}


def layer(ind, name, items, op, p=None, s=None, o=None, r=None):
    return {
        "ddd": 0, "ind": ind, "ty": 4, "nm": name, "sr": 1, "ao": 0, "bm": 0,
        "ks": {"o": o or static(100), "r": r or static(0), "p": p or static([0, 0, 0]),
               "a": static([0, 0, 0]), "s": s or static([100, 100, 100])},
        "shapes": [{"ty": "gr", "nm": name, "it": items + [tr()]}],
        "ip": 0, "op": op, "st": 0,
    }


def comp(name, w, h, op, layers):
    return {"v": "5.7.4", "fr": FPS, "ip": 0, "op": op, "w": w, "h": h, "nm": name, "ddd": 0,
            "assets": [], "layers": layers}


PINK = [0.686, 0.137, 0.396]
ROSE = [0.996, 0.392, 0.639]
GREEN = [0.2, 0.62, 0.45]
RED = [0.83, 0.2, 0.25]


def loading():
    """Tiga titik yang melompat bergantian dengan efek pegas (squash & stretch)."""
    op, cy = 60, 42
    layers = []
    for i in range(3):
        x, d = 30 + i * 30, i * 8
        base = [x, cy, 0]
        up = [x, cy - 20, 0]
        p = kf([(0, base, None), (d, base, EASE_OUT), (d + 14, up, EASE_IN), (d + 28, base, None), (op, base, None)])
        s = kf([(0, [100, 100, 100], None), (d, [118, 84, 100], EASE_OUT), (d + 6, [88, 114, 100], EASE_OUT),
                (d + 14, [100, 100, 100], EASE_IN), (d + 28, [122, 80, 100], EASE_OUT),
                (d + 36, [100, 100, 100], None), (op, [100, 100, 100], None)])
        layers.append(layer(i + 1, f"dot{i}", [ellipse(16), fill(PINK if i != 1 else ROSE)], op, p=p, s=s))
    return comp("loading", 120, 60, op, layers)


def burst(name, mark_items, rgb):
    """Lingkaran meletup + tanda yang tergambar + percikan partikel."""
    op, c = 72, [60, 60, 0]
    layers = [layer(1, "mark", mark_items, op, p=static(c),
                    s=kf([(0, [0, 0, 100], None), (10, [0, 0, 100], BACK), (26, [100, 100, 100], None)]))]
    ring_s = kf([(0, [0, 0, 100], None), (18, [115, 115, 100], EASE_OUT), (26, [100, 100, 100], None)])
    layers.append(layer(2, "circle", [ellipse(88), fill(rgb)], op, p=static(c), s=ring_s))
    halo = kf([(0, [60, 60, 100], None), (8, [60, 60, 100], EASE_OUT), (40, [140, 140, 100], None)])
    halo_o = kf([(0, 0, None), (8, 45, EASE_OUT), (40, 0, None)])
    layers.append(layer(3, "halo", [ellipse(88), fill(rgb)], op, p=static(c), s=halo, o=halo_o))
    for i in range(8):
        a = i * math.pi / 4 + math.pi / 8
        far = [60 + math.cos(a) * 56, 60 + math.sin(a) * 56, 0]
        near = [60 + math.cos(a) * 34, 60 + math.sin(a) * 34, 0]
        p = kf([(0, near, None), (14, near, EASE_OUT), (40, far, None)])
        o = kf([(0, 0, None), (12, 0, None), (16, 100, EASE_IN), (40, 0, None)])
        s = kf([(0, [100, 100, 100], None), (14, [100, 100, 100], EASE_IN), (40, [20, 20, 100], None)])
        layers.append(layer(4 + i, f"spark{i}", [ellipse(8 if i % 2 else 6), fill(rgb)], op, p=p, o=o, s=s))
    return comp(name, 120, 120, op, layers)


def success():
    draw = kf([(0, 0, None), (14, 0, EASE_OUT), (34, 100, None)])
    return burst("success", [path([[-18, 1], [-5, 14], [20, -12]]), trim(draw), stroke([1, 1, 1], 8)], GREEN)


def error():
    draw = kf([(0, 0, None), (14, 0, EASE_OUT), (32, 100, None)])
    items = [path([[-13, -13], [13, 13]]), path([[13, -13], [-13, 13]]), trim(draw), stroke([1, 1, 1], 8)]
    return burst("error", items, RED)


os.makedirs(OUT, exist_ok=True)
for name, data in {"loading": loading(), "success": success(), "error": error()}.items():
    with open(os.path.join(OUT, f"{name}.json"), "w", encoding="utf8") as f:
        json.dump(data, f, separators=(",", ":"))
    print(name, "ok")
