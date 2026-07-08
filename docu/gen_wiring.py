#!/usr/bin/env python3
"""Generate a wiring diagram (SVG) for the ESP32 soundboard.

Two panels:
  A) Audio path: DFPlayer Mini <-> ESP32 DevKit, DAC line-out -> 3.5 mm stereo
     jack (TRS) -> amplifier line-in (incl. the BUSY feedback pin).
  B) 5x5 key matrix <-> ESP32 (row/column GPIOs).

Vector art (no photo/Fritzing render): components are drawn as recognisable
boards with gradients so they read as "real" parts while staying versionable.

Pins taken directly from src/main.cpp:
  rows  = GPIO 19,18,5,17,16   cols = GPIO 32,33,25,26,27
  DFPlayer: TX->GPIO22, RX->GPIO23, BUSY->GPIO4, VCC->5V, GND->GND
  Audio:    DAC_L->Tip, DAC_R->Ring, line-out GND->Sleeve (GND between SPK1/SPK2)
"""

W, H = 1000, 1460
parts = []

FONT = "DejaVu Sans"
MONO = "DejaVu Sans Mono"

# ---- palette ----
BG = "#f4f5f7"
INK = "#1b1f27"
MUTE = "#5b6573"
KEY = "#c8302a"
KEY_DK = "#9a231e"
PAD = "#d9dde3"
DFP = "#3a4a8c"

WIRE = {
    "5v": "#d23b3b",
    "gnd": "#222222",
    "tx": "#2e9e4f",
    "rx": "#2f6fd2",
    "busy": "#f08a24",
    "audio_l": "#8e44ad",
    "audio_r": "#12968a",
    "row": "#8f4814",
    "col": "#7a3fb0",
}

# ---- SVG gradient definitions (give the parts a bit of real-world sheen) ----
DEFS = """<defs>
  <linearGradient id="gPcbEsp" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#2b3140"/><stop offset="1" stop-color="#161920"/>
  </linearGradient>
  <linearGradient id="gPcbDfp" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#3a4488"/><stop offset="1" stop-color="#1b2144"/>
  </linearGradient>
  <linearGradient id="gGold" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#f6d987"/><stop offset="1" stop-color="#c39a2c"/>
  </linearGradient>
  <linearGradient id="gMetal" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#f3f5f8"/><stop offset="0.5" stop-color="#c9ced7"/>
    <stop offset="1" stop-color="#a5abb6"/>
  </linearGradient>
  <linearGradient id="gShield" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#eaedf2"/><stop offset="1" stop-color="#b3b9c4"/>
  </linearGradient>
  <linearGradient id="gBarrel" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#454545"/><stop offset="1" stop-color="#161616"/>
  </linearGradient>
</defs>"""


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


def gold_pad(x, y):
    # A through-hole header pad: gold ring on the board edge.
    parts.append(
        f'<rect x="{x-9}" y="{y-7}" width="18" height="14" rx="3" '
        f'fill="url(#gGold)" stroke="#8a6d1e" stroke-width="1"/>'
    )
    parts.append(f'<circle cx="{x}" cy="{y}" r="3.2" fill="#2b2410"/>')


# ===== background + defs =====
parts.append(DEFS)
rect(0, 0, W, H, BG, rx=0)

# ===== title =====
text(W / 2, 44, "Soundboard – Verkabelung (ESP32 + DFPlayer Mini)",
     size=26, anchor="middle", weight="bold")
text(W / 2, 70,
     "5×5-Tastenmatrix · DFPlayer-DAC → 3,5 mm Stereo-Klinke (Line Out) · BUSY-Rückmeldung",
     size=14, anchor="middle", fill=MUTE)

# =====================================================================
#  PANEL A — Audio path (realistic component style)
# =====================================================================
pax, pay, paw, pah = 30, 96, 940, 648
rect(pax, pay, paw, pah, "#ffffff", rx=14, stroke="#d2d7df", sw=2)
text(pax + 20, pay + 34,
     "A · Audio: DFPlayer Mini ↔ ESP32 · DAC → Line Out (3,5 mm Klinke → Endstufe)",
     size=18, weight="bold")

# shared vertical positions for the 5 ESP<->DFPlayer signal rows
row_y = [350, 392, 434, 476, 518]

# ---------------------------------------------------------------
#  DFPlayer Mini (centre)
# ---------------------------------------------------------------
dfx, dfy, dfw, dfh = 400, 250, 200, 300
rect(dfx, dfy, dfw, dfh, "url(#gPcbDfp)", rx=10, stroke="#0e1230", sw=2)
text(dfx + dfw / 2, dfy + 26, "DFPlayer Mini", size=15, anchor="middle",
     fill="#d7dcf5", weight="bold")
# microSD cage (metal)
rect(dfx + 34, dfy + 40, dfw - 68, 54, "url(#gMetal)", rx=6,
     stroke="#8f95a1", sw=1.5)
rect(dfx + 46, dfy + 50, dfw - 92, 16, "#8b91a0", rx=3)
text(dfx + dfw / 2, dfy + 84, "microSD", size=11, anchor="middle", fill="#3c424c")

# right-edge header (faces the ESP): VCC/RX/TX/BUSY/GND
dfp_right = [("VCC", "5v"), ("RX", "rx"), ("TX", "tx"), ("BUSY", "busy"), ("GND", "gnd")]
dfp_right_x = dfx + dfw
for (name, _key), yy in zip(dfp_right, row_y):
    gold_pad(dfp_right_x, yy)
    text(dfp_right_x - 14, yy + 4, name, size=12, anchor="end",
         fill="#eaecf7", font=MONO)

# left-edge header (faces the jack): DAC_L / DAC_R / GND (line-out)
audio_y = [366, 426, 486]
dfp_left = [("DAC_L", "audio_l"), ("DAC_R", "audio_r"), ("GND", "gnd")]
for (name, _key), yy in zip(dfp_left, audio_y):
    gold_pad(dfx, yy)
    text(dfx + 14, yy + 4, name, size=12, anchor="start",
         fill="#eaecf7", font=MONO)

# ---------------------------------------------------------------
#  ESP32 DevKit (right)
# ---------------------------------------------------------------
ex, ey, ew, eh = 720, 190, 185, 400
rect(ex, ey, ew, eh, "url(#gPcbEsp)", rx=10, stroke="#0b0d12", sw=2)
# antenna meander at the very top
ax = ex + ew / 2 - 40
mdr = "M " + " ".join(
    f"{ax + i*10},{ey + 12 + (6 if i % 2 else 0)}" for i in range(9)
)
parts.append(f'<path d="{mdr}" fill="none" stroke="#cfd3da" stroke-width="2"/>')
# RF shield (WROOM can)
rect(ex + 20, ey + 24, ew - 40, 92, "url(#gShield)", rx=6, stroke="#8f95a1", sw=1.5)
text(ex + ew / 2, ey + 66, "ESP-WROOM-32", size=11, anchor="middle",
     fill="#3c424c", weight="bold")
text(ex + ew / 2, ey + 84, "WiFi · BT", size=9, anchor="middle", fill="#6b7280")
text(ex + ew / 2, ey + 138, "ESP32 DevKit V1", size=15, anchor="middle",
     fill="#eef2ee", weight="bold")
# micro-USB at the bottom edge
rect(ex + ew / 2 - 26, ey + eh - 22, 52, 22, "url(#gMetal)", rx=4,
     stroke="#8f95a1", sw=1.5)
text(ex + ew / 2, ey + eh - 30, "USB", size=10, anchor="middle", fill="#cfd3da")

# left-edge header (faces DFPlayer): 5V / G23 / G22 / G4 / GND
esp_left = [("5V", "5v"), ("G23 (TX2)", "rx"), ("G22 (RX2)", "tx"),
            ("G4", "busy"), ("GND", "gnd")]
for (name, _key), yy in zip(esp_left, row_y):
    gold_pad(ex, yy)
    text(ex + 14, yy + 4, name, size=11, anchor="start",
         fill="#eef2ee", font=MONO)
# a few unused pads on the right edge, for a board-like look
for i in range(6):
    yy = ey + 210 + i * 30
    gold_pad(ex + ew, yy)

# ---------------------------------------------------------------
#  wires ESP <-> DFPlayer (straight, aligned rows)
# ---------------------------------------------------------------
for (name, key), yy in zip(dfp_right, row_y):
    wire([(dfp_right_x + 9, yy), (ex - 9, yy)], WIRE[key])
# 1 kΩ series resistor on the RX line (ESP G23 -> DFPlayer RX)
ry = row_y[1]
rmx = (dfp_right_x + ex) / 2
parts.append(
    f'<rect x="{rmx-26}" y="{ry-9}" width="52" height="18" rx="3" '
    f'fill="#f3ead0" stroke="#9a7d2e" stroke-width="2"/>'
)
text(rmx, ry - 14, "1 kΩ", size=11, anchor="middle", fill="#7a6320", weight="bold")

# ---------------------------------------------------------------
#  3.5 mm stereo jack (TRS), vertical, tip up, left of the DFPlayer
#  Bands aligned to the DFPlayer DAC/GND pads: Tip=L, Ring=R, Sleeve=GND.
# ---------------------------------------------------------------
jx = 250            # jack axis
jw = 26             # metal band width
# metal shaft segments (tip -> ring -> sleeve), attach points at audio_y
segs = [
    ("tip", audio_y[0] - 22, 44),   # y0, height
    ("ring", audio_y[1] - 18, 40),
    ("sleeve", audio_y[2] - 18, 40),
]
# tip cap (rounded top)
parts.append(
    f'<path d="M {jx-jw/2},{audio_y[0]+6} '
    f'L {jx-jw/2},{audio_y[0]-16} Q {jx},{audio_y[0]-34} {jx+jw/2},{audio_y[0]-16} '
    f'L {jx+jw/2},{audio_y[0]+6} Z" fill="url(#gMetal)" stroke="#8f95a1" stroke-width="1.5"/>'
)
for _name, y0, hh in segs[1:]:
    rect(jx - jw / 2, y0, jw, hh, "url(#gMetal)", rx=3, stroke="#8f95a1", sw=1.5)
# black insulator gaps between the bands
for gy in (audio_y[0] + 6, audio_y[1] + 22):
    rect(jx - jw / 2 - 1, gy, jw + 2, 8, "#111", rx=1)
# barrel / grip below the sleeve, then the cable running off downwards
rect(jx - 18, audio_y[2] + 22, 36, 70, "url(#gBarrel)", rx=8, stroke="#0a0a0a", sw=1)
wire([(jx, audio_y[2] + 92), (jx, 610), (jx + 120, 630)], "#2a2a2a", w=8)
text(jx + 130, 634, "→ Endstufe (Line-In)", size=12, anchor="start", fill=MUTE)
text(jx, 662, "3,5 mm Stereo-Klinke (Line Out)", size=12, anchor="middle",
     fill=INK, weight="bold")

# band labels (left of the jack)
for lbl, yy in zip(["Tip · L", "Ring · R", "Sleeve · GND"], audio_y):
    text(jx - jw / 2 - 12, yy + 4, lbl, size=11, anchor="end", fill=MUTE, font=MONO)

# audio wires: DFPlayer DAC/GND pads -> jack bands (straight, aligned)
for (name, key), yy in zip(dfp_left, audio_y):
    wire([(dfx - 9, yy), (jx + jw / 2 + 1, yy)], WIRE[key])

# note
text(pax + 24, pay + pah - 20,
     "DAC_R/DAC_L = Line-Pegel → Endstufe · Line-Out-GND am DFPlayer-GND zwischen SPK1/SPK2 "
     "· BUSY (GPIO4) meldet „spielt gerade\".",
     size=12, fill=MUTE)

# =====================================================================
#  PANEL B — Key matrix
# =====================================================================
pbx, pby, pbw, pbh = 30, 764, 940, 656
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
