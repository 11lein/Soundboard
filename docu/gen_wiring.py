#!/usr/bin/env python3
"""Generate a clean wiring diagram (SVG) for the ESP32 soundboard.

Two panels:
  A) Audio path: DFPlayer Mini <-> ESP32 <-> speaker (incl. the BUSY pin).
  B) 5x5 key matrix <-> ESP32 (row/column GPIOs).

Pins taken directly from src/main.cpp:
  rows  = GPIO 19,18,5,17,16   cols = GPIO 32,33,25,26,27
  DFPlayer: TX->GPIO22, RX->GPIO23, BUSY->GPIO4, VCC->5V, GND->GND
"""

W, H = 1000, 1300
parts = []

FONT = "DejaVu Sans"
MONO = "DejaVu Sans Mono"

# ---- palette ----
BG = "#f4f5f7"
BOARD = "#2f6f4f"        # ESP board green
BOARD_DK = "#24573e"
DFP = "#3a4a8c"          # DFPlayer blue
DFP_DK = "#2c3a6e"
SPK = "#3a3a3a"
KEY = "#c8302a"
KEY_DK = "#9a231e"
PAD = "#d9dde3"
INK = "#1b1f27"
MUTE = "#5b6573"

WIRE = {
    "5v": "#d23b3b",
    "gnd": "#222222",
    "tx": "#2e9e4f",
    "rx": "#2f6fd2",
    "busy": "#f08a24",
    "spk": "#777777",
    "row": "#8f4814",
    "col": "#7a3fb0",
}


def rect(x, y, w, h, fill, rx=8, stroke="none", sw=0, opacity=1):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke != "none" else ""
    parts.append(
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" '
        f'fill="{fill}" opacity="{opacity}"{s}/>'
    )


def text(x, y, s, size=15, fill=INK, anchor="start", weight="normal", font=FONT):
    parts.append(
        f'<text x="{x}" y="{y}" font-family="{font}" font-size="{size}" '
        f'fill="{fill}" text-anchor="{anchor}" font-weight="{weight}">{s}</text>'
    )


def wire(pts, color, w=4):
    d = "M " + " L ".join(f"{x},{y}" for x, y in pts)
    parts.append(
        f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{w}" '
        f'stroke-linecap="round" stroke-linejoin="round"/>'
    )


def dot(x, y, color, r=5):
    parts.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{color}"/>')


def pin(x, y, color="#caa23a"):
    parts.append(
        f'<circle cx="{x}" cy="{y}" r="4.5" fill="{color}" '
        f'stroke="#7a6320" stroke-width="1"/>'
    )


# ===== background =====
rect(0, 0, W, H, BG, rx=0)

# ===== title =====
text(W / 2, 44, "Soundboard – Verkabelung (ESP32 + DFPlayer Mini)",
     size=26, anchor="middle", weight="bold")
text(W / 2, 70, "5×5-Tastenmatrix · Audio über DFPlayer-Endstufe · BUSY-Rückmeldung",
     size=15, anchor="middle", fill=MUTE)

# =====================================================================
#  PANEL A — Audio path
# =====================================================================
pax, pay, paw, pah = 30, 96, 940, 496
rect(pax, pay, paw, pah, "#ffffff", rx=14, stroke="#d2d7df", sw=2)
text(pax + 20, pay + 34, "A · Audio: DFPlayer Mini ↔ ESP32 ↔ Lautsprecher",
     size=19, weight="bold")

# ---- ESP32 board (center) ----
ex, ey, ew, eh = 410, 150, 170, 340
rect(ex, ey, ew, eh, BOARD, rx=14)
rect(ex + ew / 2 - 34, ey + 14, 68, 40, "#cfd3da", rx=4)   # antenna/can
rect(ex + 30, ey + 70, ew - 60, 150, BOARD_DK, rx=8)       # chip
text(ex + ew / 2, ey + 158, "ESP32", size=22, anchor="middle",
     fill="#eef2ee", weight="bold")
rect(ex + ew / 2 - 22, ey + eh - 36, 44, 24, "#1b1b1b", rx=4)  # usb
text(ex + ew / 2, ey + eh - 19, "USB", size=11, anchor="middle", fill="#cfd3da")

# ESP right-side pins used by the DFPlayer (top group)
esp_pins_R = [
    ("5V",     "5v"),
    ("GND",    "gnd"),
    ("G23 (TX2)", "rx"),   # ESP TX -> DFPlayer RX
    ("G22 (RX2)", "tx"),   # ESP RX -> DFPlayer TX
    ("G4",     "busy"),
]
esp_pin_y = {}
py0 = ey + 90
for i, (name, key) in enumerate(esp_pins_R):
    yy = py0 + i * 46
    esp_pin_y[name] = yy
    pin(ex + ew, yy)
    text(ex + ew - 10, yy + 5, name, size=13, anchor="end",
         fill="#eef2ee", font=MONO)

# ---- DFPlayer Mini (right) ----
dx, dy, dw, dh = 700, 150, 150, 300
rect(dx, dy, dw, dh, DFP, rx=12)
text(dx + dw / 2, dy + 26, "DFPlayer", size=17, anchor="middle",
     fill="#eaecf7", weight="bold")
text(dx + dw / 2, dy + 44, "Mini", size=14, anchor="middle", fill="#c4cae8")
rect(dx + 24, dy + 58, dw - 48, 86, DFP_DK, rx=6)   # SD slot
text(dx + dw / 2, dy + 106, "microSD", size=12, anchor="middle", fill="#aeb6df")

# DFPlayer left-side pins (facing the ESP)
dfp_pins = [
    ("VCC",  "5v"),
    ("RX",   "rx"),
    ("TX",   "tx"),
    ("BUSY", "busy"),
    ("GND",  "gnd"),
]
dfp_pin_y = {}
dy0 = dy + 180
for i, (name, key) in enumerate(dfp_pins):
    yy = dy0 + i * 26
    dfp_pin_y[name] = yy
    pin(dx, yy)
    text(dx + 12, yy + 4, name, size=12, anchor="start",
         fill="#eaecf7", font=MONO)

# DFPlayer speaker pins (bottom edge -> speaker)
spk_pins = [("SPK1", dx + 40), ("SPK2", dx + dw - 40)]
for name, xx in spk_pins:
    pin(xx, dy + dh)
    text(xx, dy + dh + 18, name, size=11, anchor="middle", fill=DFP, font=MONO)

# ---- Speaker (below DFPlayer) ----
sx, sy, sr = dx + dw / 2, dy + dh + 70, 42
parts.append(f'<circle cx="{sx}" cy="{sy}" r="{sr}" fill="{SPK}"/>')
parts.append(f'<circle cx="{sx}" cy="{sy}" r="{sr-14}" fill="#555"/>')
parts.append(f'<circle cx="{sx}" cy="{sy}" r="9" fill="#222"/>')
text(sx, sy + sr + 18, "Lautsprecher", size=12, anchor="middle", fill=MUTE)

# ---- wires ESP <-> DFPlayer ----
# Each ESP pin routes to the matching DFPlayer pin with an orthogonal path.
route = [
    ("5V",        "VCC",  "5v",   612),
    ("G23 (TX2)", "RX",   "rx",   624),
    ("G22 (RX2)", "TX",   "tx",   636),
    ("G4",        "BUSY", "busy", 648),
    ("GND",       "GND",  "gnd",  664),
]
for esp_name, dfp_name, key, midx in route:
    y1 = esp_pin_y[esp_name]
    y2 = dfp_pin_y[dfp_name]
    wire([(ex + ew, y1), (midx, y1), (midx, y2), (dx, y2)], WIRE[key])

# speaker wires
wire([(dx + 40, dy + dh), (dx + 40, sy - 6), (sx - 18, sy - 6)], WIRE["spk"])
wire([(dx + dw - 40, dy + dh), (dx + dw - 40, sy + 18), (sx + 18, sy + 18)], WIRE["spk"])

# ---- connection table (left) ----
tx0, ty0 = pax + 24, 200
text(tx0, ty0 - 14, "Audio-Verbindungen", size=15, weight="bold")
audio_rows = [
    ("DFPlayer VCC", "ESP 5V", "5v"),
    ("DFPlayer RX", "ESP GPIO23 (TX2)", "rx"),
    ("DFPlayer TX", "ESP GPIO22 (RX2)", "tx"),
    ("DFPlayer BUSY", "ESP GPIO4", "busy"),
    ("DFPlayer GND", "ESP GND", "gnd"),
    ("DFPlayer SPK1/SPK2", "Lautsprecher", "spk"),
]
for i, (a, b, key) in enumerate(audio_rows):
    yy = ty0 + 18 + i * 32
    parts.append(
        f'<rect x="{tx0}" y="{yy-13}" width="14" height="14" rx="3" '
        f'fill="{WIRE[key]}"/>'
    )
    text(tx0 + 24, yy, a, size=13, font=MONO)
    text(tx0 + 24, yy + 14, "→ " + b, size=12, fill=MUTE, font=MONO)
    ty0 += 14

# highlight note for BUSY (the new wire)
text(pax + 24, pay + pah - 18,
     "★ Neu: BUSY (GPIO4) meldet \"spielt gerade\" – kein Serial-Polling mehr.",
     size=13, fill=WIRE["busy"], weight="bold")

# =====================================================================
#  PANEL B — Key matrix
# =====================================================================
pbx, pby, pbw, pbh = 30, 612, 940, 656
rect(pbx, pby, pbw, pbh, "#ffffff", rx=14, stroke="#d2d7df", sw=2)
text(pbx + 20, pby + 34, "B · Tastenmatrix 5×5 ↔ ESP32 (24 Tasten A–X + Mode-Taste Y)",
     size=19, weight="bold")

# matrix geometry
letters = [
    ["A", "B", "C", "D", "E"],
    ["F", "G", "H", "I", "J"],
    ["K", "L", "M", "N", "O"],
    ["P", "Q", "R", "S", "T"],
    ["U", "V", "W", "X", "Y"],
]
row_gpio = ["GPIO19", "GPIO18", "GPIO5", "GPIO17", "GPIO16"]
col_gpio = ["GPIO32", "GPIO33", "GPIO25", "GPIO26", "GPIO27"]

m_left = pbx + 205
m_top = pby + 116
step = 104
key_r = 24

# column bus lines (vertical) + labels at top
for c in range(5):
    cx = m_left + c * step
    y_top = m_top - 40
    y_bot = m_top + 4 * step + 40
    wire([(cx, y_top), (cx, y_bot)], WIRE["col"], w=3)
    parts.append(
        f'<rect x="{cx-34}" y="{y_top-26}" width="68" height="20" rx="4" '
        f'fill="{WIRE["col"]}"/>'
    )
    text(cx, y_top - 11, col_gpio[c], size=11, anchor="middle",
         fill="#fff", font=MONO)
    text(cx, y_bot + 22, f"C{c+1}", size=13, anchor="middle",
         fill=WIRE["col"], weight="bold")

# row bus lines (horizontal) + labels at left
for r in range(5):
    ry = m_top + r * step
    x_l = m_left - 80
    x_r = m_left + 4 * step + 40
    wire([(x_l, ry), (x_r, ry)], WIRE["row"], w=3)
    parts.append(
        f'<rect x="{x_l-72}" y="{ry-12}" width="72" height="22" rx="4" '
        f'fill="{WIRE["row"]}"/>'
    )
    text(x_l - 36, ry + 4, row_gpio[r], size=11, anchor="middle",
         fill="#fff", font=MONO)
    text(x_r + 26, ry + 5, f"R{r+1}", size=13, anchor="middle",
         fill=WIRE["row"], weight="bold")

# keys at intersections (each bridges its row + column)
for r in range(5):
    for c in range(5):
        cx = m_left + c * step
        cy = m_top + r * step
        is_mode = letters[r][c] == "Y"
        fill = PAD if is_mode else KEY
        edge = "#9aa0ad" if is_mode else KEY_DK
        # contact stubs to row and column
        dot(cx, cy, edge, r=key_r + 4)
        parts.append(
            f'<circle cx="{cx}" cy="{cy}" r="{key_r}" fill="{fill}" '
            f'stroke="{edge}" stroke-width="3"/>'
        )
        text(cx, cy + 6, letters[r][c], size=18, anchor="middle",
             fill=("#1b1f27" if is_mode else "#fff"), weight="bold")
        if is_mode:
            text(cx, cy + key_r + 18, "MODE", size=10, anchor="middle",
                 fill=MUTE, weight="bold")

# legend (bottom of panel B)
ly = pby + pbh - 16
text(pbx + 24, ly, "Zeilen (R1–R5):", size=13, weight="bold", fill=WIRE["row"])
text(pbx + 170, ly, "GPIO 19 · 18 · 5 · 17 · 16", size=13, font=MONO)
text(pbx + 470, ly, "Spalten (C1–C5):", size=13, weight="bold", fill=WIRE["col"])
text(pbx + 640, ly, "GPIO 32 · 33 · 25 · 26 · 27", size=13, font=MONO)

svg = (
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
    f'viewBox="0 0 {W} {H}">\n' + "\n".join(parts) + "\n</svg>\n"
)
open("/tmp/wiring.svg", "w", encoding="utf-8").write(svg)
print("wrote /tmp/wiring.svg")
