"""Generate a PowerPoint presentation for the baaad-strategy repo."""

import io
import os
import tempfile

from PIL import Image, ImageDraw, ImageFont
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.util import Inches, Pt
import copy

# ── Palette ──────────────────────────────────────────────────────────────────
DARK_GREEN   = RGBColor(0x1A, 0x3D, 0x1A)   # slide background / title bg
MID_GREEN    = RGBColor(0x2E, 0x7D, 0x32)   # accent bars
LIGHT_GREEN  = RGBColor(0x8E, 0xCF, 0x3A)   # "pasture" highlight
CREAM        = RGBColor(0xFF, 0xFB, 0xF0)   # body text background
OFF_WHITE    = RGBColor(0xF5, 0xF5, 0xF0)   # slide bg
DARK_TEXT    = RGBColor(0x1A, 0x1A, 0x1A)
RED_ACCENT   = RGBColor(0xBB, 0x11, 0x11)
GOLD         = RGBColor(0xE8, 0xC0, 0x30)

# Resource colours — match terrain colours from visualize_board.R
RES_LUMBER = RGBColor(0x3A, 0x7D, 0x2C)   # forest green
RES_BRICK  = RGBColor(0xB8, 0x4A, 0x1A)   # brick red
RES_WOOL   = RGBColor(0x4A, 0x9A, 0x10)   # pasture green (slightly darker for readability)
RES_GRAIN  = RGBColor(0xC0, 0x90, 0x08)   # fields gold (darkened for readability)
RES_ORE    = RGBColor(0x6A, 0x6A, 0x7A)   # mountain grey

SLIDE_W = Inches(13.33)
SLIDE_H = Inches(7.5)

# ── Hex-sticker PNG (rendered from hex-sticker.svg via Pillow) ────────────────

def _render_hex_sticker(path, render_height=924):
    """Draw the baaad-strategy hex sticker with Pillow and save as PNG."""
    sc = render_height / 231          # SVG viewBox height = 231
    W  = round(200 * sc)
    H  = render_height

    img  = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    def p(x, y):   return (round(x * sc), round(y * sc))
    def ps(pts):   return [p(x, y) for x, y in pts]
    def ell(cx, cy, rx, ry=None):
        ry = rx if ry is None else ry
        return [round((cx - rx)*sc), round((cy - ry)*sc),
                round((cx + rx)*sc), round((cy + ry)*sc)]
    def rct(x, y, w, h):
        return [round(x*sc), round(y*sc), round((x+w)*sc), round((y+h)*sc)]

    HEX = [(100,5),(190,52.5),(190,178.5),(100,226),(10,178.5),(10,52.5)]

    # Background
    draw.polygon(ps(HEX), fill=(40, 80, 22))

    # Subtle hex grid (low-opacity outline only)
    for gpts in [
        [(100,28),(128,44),(128,76),(100,92),(72,76),(72,44)],
        [(52,66),(80,82),(80,114),(52,130),(24,114),(24,82)],
        [(148,66),(176,82),(176,114),(148,130),(120,114),(120,82)],
        [(100,108),(128,124),(128,156),(100,172),(72,156),(72,124)],
    ]:
        draw.polygon(ps(gpts), outline=(168, 216, 120, 28))

    # Tail
    draw.ellipse(ell(138, 126, 9),  fill=(245, 242, 236))
    # Wool body
    for cx, cy, r, fill in [
        (105, 122, 28, (237, 234, 224)),
        (84,  114, 21, (245, 242, 236)),
        (93,  101, 21, (245, 242, 236)),
        (112,  99, 21, (245, 242, 236)),
        (126, 111, 19, (245, 242, 236)),
        (129, 127, 15, (237, 234, 224)),
        (80,  128, 15, (237, 234, 224)),
    ]:
        draw.ellipse(ell(cx, cy, r), fill=fill)

    # Head
    draw.ellipse(ell(62, 131, 16, 13), fill=(202, 194, 184))
    # Ear outer / inner
    draw.ellipse(ell(66, 119,  6,  9), fill=(202, 194, 184))
    draw.ellipse(ell(66, 120,  4,  6), fill=(196, 144, 128))
    # Eye + highlight
    draw.ellipse(ell(55, 128, 2.8),    fill=(26,  26,  26))
    draw.ellipse(ell(54, 127, 0.9),    fill=(255, 255, 255))
    # Nostril
    draw.ellipse(ell(50,   135, 3.5, 2.5), fill=(176, 168, 158))
    draw.ellipse(ell(49,   135, 1.0),      fill=(138, 128, 122))
    draw.ellipse(ell(51.5, 135, 1.0),      fill=(138, 128, 122))

    # Legs + hooves
    leg_r = round(4 * sc)
    for lx in [84, 97, 110, 121]:
        draw.rounded_rectangle(rct(lx, 148, 8, 22), radius=leg_r,  fill=(202, 194, 184))
    for hx, hy in [(84,166),(97,167),(110,167),(121,166)]:
        draw.rounded_rectangle(rct(hx, hy,  8,  4), radius=round(2*sc), fill=(90, 80, 72))

    # Text — "baaad" and "STRATEGY"
    font_big = font_small = font_tiny = None
    for font_name in ["georgiab.ttf", "Georgia Bold.ttf", "arialbd.ttf", "Arial Bold.ttf"]:
        try:
            font_big = ImageFont.truetype(font_name, round(18 * sc))
            break
        except Exception:
            pass
    for font_name in ["georgia.ttf", "Georgia.ttf", "arial.ttf", "Arial.ttf"]:
        try:
            font_small = ImageFont.truetype(font_name, round(11 * sc))
            font_tiny  = ImageFont.truetype(font_name, round(9 * sc))
            break
        except Exception:
            pass

    def centre_text(draw, y_svg, text, font, color):
        if font is None:
            return
        bbox = draw.textbbox((0, 0), text, font=font)
        tw = bbox[2] - bbox[0]
        x  = (W - tw) // 2
        draw.text((x, round(y_svg * sc)), text, font=font, fill=color)

    centre_text(draw, 26, "baaad",    font_big,   (212, 240, 160))
    centre_text(draw, 48, "STRATEGY", font_small, (168, 204, 120))
    centre_text(draw, 188, "Catan Simulation", font_tiny, (168, 204, 120))

    # Hex border
    draw.polygon(ps(HEX), outline=(168, 216, 120), width=round(4 * sc))

    # Downsample 2× for anti-aliasing
    img = img.resize((W // 2, H // 2), Image.LANCZOS)
    img.save(path, "PNG")

_STICKER_PNG = os.path.join(tempfile.gettempdir(), "baaad_sticker.png")
_render_hex_sticker(_STICKER_PNG)
REPO_URL = "github.com/ayoung31/baaad-strategy"

prs = Presentation()
prs.slide_width  = SLIDE_W
prs.slide_height = SLIDE_H

BLANK = prs.slide_layouts[6]   # completely blank


# ── Helpers ───────────────────────────────────────────────────────────────────

def bg(slide, color):
    """Fill slide background with a solid colour."""
    fill = slide.background.fill
    fill.solid()
    fill.fore_color.rgb = color


def rect(slide, l, t, w, h, fill_color=None, line_color=None, line_width=Pt(0)):
    from pptx.util import Emu
    shape = slide.shapes.add_shape(
        1,  # MSO_SHAPE_TYPE.RECTANGLE
        l, t, w, h
    )
    shape.line.width = line_width
    if fill_color:
        shape.fill.solid()
        shape.fill.fore_color.rgb = fill_color
    else:
        shape.fill.background()
    if line_color:
        shape.line.color.rgb = line_color
    else:
        shape.line.fill.background()
    return shape


def textbox(slide, text, l, t, w, h,
            font_size=Pt(18), bold=False, color=DARK_TEXT,
            align=PP_ALIGN.LEFT, italic=False, wrap=True):
    txb = slide.shapes.add_textbox(l, t, w, h)
    tf  = txb.text_frame
    tf.word_wrap = wrap
    p = tf.paragraphs[0]
    p.alignment = align
    run = p.add_run()
    run.text = text
    run.font.size  = font_size
    run.font.bold  = bold
    run.font.color.rgb = color
    run.font.italic = italic
    return txb


def add_bullet_slide(title_text, bullets, accent_color=MID_GREEN):
    """Standard content slide with a coloured top bar and bullet list."""
    slide = prs.slides.add_slide(BLANK)
    bg(slide, OFF_WHITE)

    # top bar
    rect(slide, 0, 0, SLIDE_W, Inches(1.1), fill_color=accent_color)

    # title
    textbox(slide, title_text,
            Inches(0.4), Inches(0.12), Inches(12.5), Inches(0.9),
            font_size=Pt(32), bold=True, color=CREAM)

    # bullet area background
    rect(slide, Inches(0.3), Inches(1.25), Inches(12.7), Inches(5.9),
         fill_color=CREAM, line_color=RGBColor(0xCC,0xCC,0xBB), line_width=Pt(0.75))

    # bullets
    txb = slide.shapes.add_textbox(Inches(0.55), Inches(1.4), Inches(12.2), Inches(5.6))
    tf  = txb.text_frame
    tf.word_wrap = True

    for i, (indent, text) in enumerate(bullets):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.level = indent
        if indent == 0:
            bullet_char = "▸  "
            fsize = Pt(20)
            fbold = True
            fcolor = DARK_GREEN
        else:
            bullet_char = "     •  "
            fsize = Pt(17)
            fbold = False
            fcolor = DARK_TEXT
        run = p.add_run()
        run.text = bullet_char + text
        run.font.size  = fsize
        run.font.bold  = fbold
        run.font.color.rgb = fcolor

    return slide


def add_two_col_slide(title_text, left_title, left_rows, right_title, right_rows,
                      accent_color=MID_GREEN):
    slide = prs.slides.add_slide(BLANK)
    bg(slide, OFF_WHITE)
    rect(slide, 0, 0, SLIDE_W, Inches(1.1), fill_color=accent_color)
    textbox(slide, title_text,
            Inches(0.4), Inches(0.12), Inches(12.5), Inches(0.9),
            font_size=Pt(32), bold=True, color=CREAM)

    col_w = Inches(6.0)
    col_h = Inches(5.9)
    gap   = Inches(0.35)
    top   = Inches(1.25)

    for col_idx, (col_title, rows) in enumerate(
            [(left_title, left_rows), (right_title, right_rows)]):
        left = Inches(0.3) + col_idx * (col_w + gap)
        rect(slide, left, top, col_w, col_h,
             fill_color=CREAM,
             line_color=RGBColor(0xCC,0xCC,0xBB), line_width=Pt(0.75))

        # column header
        rect(slide, left, top, col_w, Inches(0.5), fill_color=DARK_GREEN)
        textbox(slide, col_title,
                left + Inches(0.1), top + Inches(0.05),
                col_w - Inches(0.2), Inches(0.45),
                font_size=Pt(16), bold=True, color=CREAM, align=PP_ALIGN.CENTER)

        txb = slide.shapes.add_textbox(
            left + Inches(0.2), top + Inches(0.6),
            col_w - Inches(0.3), col_h - Inches(0.7))
        tf = txb.text_frame
        tf.word_wrap = True
        for i, line in enumerate(rows):
            p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
            run = p.add_run()
            run.text = line
            run.font.size  = Pt(15)
            run.font.color.rgb = DARK_TEXT

    return slide


def add_table_slide(title_text, headers, rows_data, accent_color=MID_GREEN,
                    col_widths=None):
    from pptx.util import Inches, Pt
    slide = prs.slides.add_slide(BLANK)
    bg(slide, OFF_WHITE)
    rect(slide, 0, 0, SLIDE_W, Inches(1.1), fill_color=accent_color)
    textbox(slide, title_text,
            Inches(0.4), Inches(0.12), Inches(12.5), Inches(0.9),
            font_size=Pt(32), bold=True, color=CREAM)

    n_cols = len(headers)
    n_rows = len(rows_data) + 1   # +1 for header
    tbl_w  = Inches(12.5)
    tbl_h  = Inches(5.6)
    tbl_l  = Inches(0.4)
    tbl_t  = Inches(1.3)

    table = slide.shapes.add_table(n_rows, n_cols, tbl_l, tbl_t, tbl_w, tbl_h).table

    if col_widths:
        for ci, cw in enumerate(col_widths):
            table.columns[ci].width = cw

    # header row
    for ci, hdr in enumerate(headers):
        cell = table.cell(0, ci)
        cell.text = hdr
        cell.fill.solid()
        cell.fill.fore_color.rgb = DARK_GREEN
        p = cell.text_frame.paragraphs[0]
        p.alignment = PP_ALIGN.CENTER
        run = p.runs[0]
        run.font.bold  = True
        run.font.size  = Pt(15)
        run.font.color.rgb = CREAM

    # data rows
    for ri, row in enumerate(rows_data):
        fill_color = CREAM if ri % 2 == 0 else RGBColor(0xE8, 0xF0, 0xE0)
        for ci, val in enumerate(row):
            cell = table.cell(ri + 1, ci)
            cell.text = val
            cell.fill.solid()
            cell.fill.fore_color.rgb = fill_color
            p = cell.text_frame.paragraphs[0]
            p.alignment = PP_ALIGN.LEFT
            run = p.runs[0]
            run.font.size  = Pt(14)
            run.font.color.rgb = DARK_TEXT

    return slide


# ══════════════════════════════════════════════════════════════════════════════
# Slide 1 — Title
# ══════════════════════════════════════════════════════════════════════════════
slide = prs.slides.add_slide(BLANK)
bg(slide, DARK_GREEN)

# big decorative hex pattern (simple circles as stand-in)
for i, (cx, cy, r, alpha_color) in enumerate([
    (Inches(11.5), Inches(1.0), Inches(1.6), RGBColor(0x2E,0x5A,0x2E)),
    (Inches(12.4), Inches(2.8), Inches(1.1), RGBColor(0x26,0x4E,0x26)),
    (Inches(10.5), Inches(2.5), Inches(0.8), RGBColor(0x22,0x44,0x22)),
]):
    shape = slide.shapes.add_shape(9, cx - r, cy - r, r*2, r*2)  # oval
    shape.fill.solid()
    shape.fill.fore_color.rgb = alpha_color
    shape.line.fill.background()

# accent bar
rect(slide, 0, Inches(2.6), SLIDE_W, Inches(0.08), fill_color=LIGHT_GREEN)

# main title
txb = slide.shapes.add_textbox(Inches(0.6), Inches(0.8), Inches(10), Inches(1.8))
tf = txb.text_frame
tf.word_wrap = False
p = tf.paragraphs[0]
run = p.add_run()
run.text = "baaad-strategy"
run.font.size  = Pt(56)
run.font.bold  = True
run.font.color.rgb = LIGHT_GREEN

# subtitle
txb2 = slide.shapes.add_textbox(Inches(0.6), Inches(2.75), Inches(11), Inches(1.2))
tf2 = txb2.text_frame
tf2.word_wrap = True
p2 = tf2.paragraphs[0]
run2 = p2.add_run()
run2.text = "A Monte Carlo simulation proving the sheep strategy in Catan is baaad"
run2.font.size  = Pt(26)
run2.font.color.rgb = CREAM
run2.font.italic = True

# tagline
txb3 = slide.shapes.add_textbox(Inches(0.6), Inches(4.1), Inches(11), Inches(0.8))
tf3 = txb3.text_frame
p3 = tf3.paragraphs[0]
run3 = p3.add_run()
run3.text = "Built in R  ·  1,000 simulated games  ·  χ² statistical significance testing"
run3.font.size  = Pt(18)
run3.font.color.rgb = GOLD

# bottom label
textbox(slide, REPO_URL,
        Inches(0.6), Inches(6.8), Inches(6), Inches(0.5),
        font_size=Pt(13), color=RGBColor(0x88,0xAA,0x88))

# Hex sticker — top-right corner
sticker_h = Inches(2.9)
sticker_w = sticker_h * (200 / 231)
slide.shapes.add_picture(_STICKER_PNG,
                         SLIDE_W - sticker_w - Inches(0.3),
                         Inches(0.25),
                         sticker_w, sticker_h)


# ══════════════════════════════════════════════════════════════════════════════
# Slide 2 — What is this project?
# ══════════════════════════════════════════════════════════════════════════════
add_bullet_slide(
    "What Is This Project?",
    [
        (0, "Settle the debate: is going all-in on sheep actually a good Catan strategy?"),
        (1, "The 'sheep strategy' — settle on high-wool hexes, race to the 2:1 Wool port"),
        (1, "Sounds clever in theory; this project tests it statistically"),
        (0, "Approach: Monte Carlo simulation in R"),
        (1, "Run 1,000 full Catan games with three competing strategies"),
        (1, "Compare win rates using a chi-squared significance test (p < 0.05)"),
        (0, "Result: sheep strategy loses significantly — the numbers don't lie"),
        (1, "Reproducible with a fixed random seed"),
        (1, "All results written to results/simulation_results.csv"),
    ]
)


# ══════════════════════════════════════════════════════════════════════════════
# Slide 3 — The Three Strategies
# ══════════════════════════════════════════════════════════════════════════════
add_table_slide(
    "The Three Competing Strategies",
    ["Strategy", "Initial Placement", "Road Priority", "Build Priority"],
    [
        ["balanced_strategy",
         "Maximise pip count + resource diversity",
         "Expand toward best open spots",
         "Ore + Grain for cities; use best port"],
        ["sheep_strategy",
         "Score intersections by adjacent wool pips",
         "Route roads to the 2:1 Wool port",
         "Surplus wool → dev cards"],
        ["ore_grain_strategy",
         "Prioritise ore and grain hexes",
         "Connect to ore/grain hexes",
         "Fast-track city upgrades"],
    ],
    col_widths=[Inches(2.2), Inches(3.3), Inches(3.3), Inches(3.4)],
)


# ══════════════════════════════════════════════════════════════════════════════
# Slide 4 — Why Sheep Should Lose (Hypothesis)
# ══════════════════════════════════════════════════════════════════════════════
add_bullet_slide(
    "The Hypothesis: Why Sheep Loses",
    [
        (0, "Wool is structurally the weakest late-game resource"),
        (1, "Needed for settlements & dev cards — but NOT cities"),
        (1, "Cities (3 Ore + 2 Grain) are the primary VP-scaling mechanism"),
        (0, "Wool is the most abundant resource on the board"),
        (1, "4 Pasture hexes vs. only 3 Mountains and 3 Hills"),
        (1, "Opponents naturally produce plenty of wool — the 2:1 port is less of an edge than 2:1 Ore or 2:1 Grain"),
        (0, "Placement trade-off hurts city-building"),
        (1, "Prioritising wool hexes means sacrificing better ore/grain spots"),
        (1, "A wool surplus with no matching ore/grain cannot efficiently convert to VP"),
        (0, "Success criterion: sheep win rate significantly lower than balanced (p < 0.05)"),
    ],
    accent_color=RED_ACCENT,
)


# ══════════════════════════════════════════════════════════════════════════════
# Slide 5 — Catan Primer: Resources & Building Costs (with coloured symbols)
# ══════════════════════════════════════════════════════════════════════════════

# Each cost is a list of (text, colour) runs.  ● is the resource symbol.
# Plain text segments use DARK_TEXT; resource dots use their own colour.
_T = DARK_TEXT   # shorthand

RESOURCE_COSTS = [
    # (item, vp, strategic_value, cost_runs)
    ("Road", "0", "Expands network; needed for Longest Road",
     [("●", RES_LUMBER), (" Lumber  ", _T),
      ("●", RES_BRICK),  (" Brick", _T)]),

    ("Settlement", "1", "Unlocks new production spots",
     [("●", RES_LUMBER), (" Lumber  ", _T),
      ("●", RES_BRICK),  (" Brick  ", _T),
      ("●", RES_WOOL),   (" Wool  ", _T),
      ("●", RES_GRAIN),  (" Grain", _T)]),

    ("City\n(upgrade)", "+1", "Doubles production; primary VP engine",
     [("●●●", RES_ORE),   (" Ore  ", _T),
      ("●●",  RES_GRAIN), (" Grain", _T)]),

    ("Dev Card", "varies", "Knights (Largest Army) or VP cards",
     [("●", RES_ORE),   (" Ore  ", _T),
      ("●", RES_WOOL),  (" Wool  ", _T),
      ("●", RES_GRAIN), (" Grain", _T)]),

    ("Largest Army", "2", "Hold the most knight cards (≥ 3)",
     [("3+ Knight cards", _T)]),

    ("Longest Road", "2", "Early game bonus for road builders",
     [("5+ continuous road segments", _T)]),
]

def add_resource_primer_slide():
    slide = prs.slides.add_slide(BLANK)
    bg(slide, OFF_WHITE)
    rect(slide, 0, 0, SLIDE_W, Inches(1.1), fill_color=MID_GREEN)
    textbox(slide, "Catan Primer: Resources & Building Costs",
            Inches(0.4), Inches(0.12), Inches(12.5), Inches(0.9),
            font_size=Pt(32), bold=True, color=CREAM)

    headers = ["Item", "Cost", "VP", "Strategic Value"]
    col_widths = [Inches(1.7), Inches(3.4), Inches(0.8), Inches(6.2)]
    n_rows = len(RESOURCE_COSTS) + 1
    n_cols = 4
    tbl_w = Inches(12.1)
    tbl_h = Inches(5.6)
    tbl_l = Inches(0.6)
    tbl_t = Inches(1.3)

    table = slide.shapes.add_table(n_rows, n_cols, tbl_l, tbl_t, tbl_w, tbl_h).table
    for ci, cw in enumerate(col_widths):
        table.columns[ci].width = cw

    # Header row
    for ci, hdr in enumerate(headers):
        cell = table.cell(0, ci)
        cell.fill.solid()
        cell.fill.fore_color.rgb = DARK_GREEN
        tf = cell.text_frame
        p  = tf.paragraphs[0]
        p.alignment = PP_ALIGN.CENTER
        run = p.add_run()
        run.text = hdr
        run.font.bold  = True
        run.font.size  = Pt(15)
        run.font.color.rgb = CREAM

    # Data rows
    for ri, (item, vp, strategy, cost_runs) in enumerate(RESOURCE_COSTS):
        fill_color = CREAM if ri % 2 == 0 else RGBColor(0xE8, 0xF0, 0xE0)

        def plain_cell(ci, text, bold=False, align=PP_ALIGN.LEFT):
            cell = table.cell(ri + 1, ci)
            cell.fill.solid()
            cell.fill.fore_color.rgb = fill_color
            tf = cell.text_frame
            tf.word_wrap = True
            p  = tf.paragraphs[0]
            p.alignment = align
            run = p.add_run()
            run.text = text
            run.font.size  = Pt(14)
            run.font.bold  = bold
            run.font.color.rgb = DARK_TEXT

        plain_cell(0, item, bold=True)

        # Cost cell — multi-run with coloured circles
        cost_cell = table.cell(ri + 1, 1)
        cost_cell.fill.solid()
        cost_cell.fill.fore_color.rgb = fill_color
        tf = cost_cell.text_frame
        tf.word_wrap = True
        p  = tf.paragraphs[0]
        p.alignment = PP_ALIGN.LEFT
        for text, color in cost_runs:
            run = p.add_run()
            run.text = text
            run.font.size  = Pt(15)
            run.font.bold  = (color != _T)   # bold the circle symbols
            run.font.color.rgb = color

        plain_cell(2, vp, align=PP_ALIGN.CENTER)
        plain_cell(3, strategy)

    return slide

add_resource_primer_slide()


# ══════════════════════════════════════════════════════════════════════════════
# Slide 6 — Board & Dice Probabilities
# ══════════════════════════════════════════════════════════════════════════════
add_two_col_slide(
    "Board Setup & Dice Probabilities",
    "Terrain Hex Counts",
    [
        "19 hexes total:",
        "",
        "▸  Forest (Lumber)   — 4 hexes",
        "▸  Pasture (Wool)    — 4 hexes   ← most abundant",
        "▸  Fields (Grain)    — 4 hexes",
        "▸  Hills (Brick)     — 3 hexes",
        "▸  Mountains (Ore)   — 3 hexes   ← scarcest",
        "▸  Desert            — 1 hex",
        "",
        "9 ports around the coast:",
        "  4 × General (3:1)  |  5 × Specific (2:1)",
    ],
    "Number Token Probabilities",
    [
        "Token  Pips  Probability",
        "─────────────────────────",
        "  6      5      5/36  ←  best",
        "  8      5      5/36  ←  best",
        "  5      4      4/36",
        "  9      4      4/36",
        "  4      3      3/36",
        " 10      3      3/36",
        "  3      2      2/36",
        " 11      2      2/36",
        "  2      1      1/36",
        " 12      1      1/36",
        "  7   (robber — not a token)",
    ],
)


# ══════════════════════════════════════════════════════════════════════════════
# Slide 7 — Architecture: 6 Modules
# ══════════════════════════════════════════════════════════════════════════════
add_bullet_slide(
    "Architecture: 6 R Modules",
    [
        (0, "board.R — Hex graph, board generation, ports"),
        (1, "19 hexes · 54 intersections · 72 road edges · axial coordinate layout"),
        (1, "generate_board() supports random terrain, tokens, and ports"),
        (0, "player.R — Player state and resource management"),
        (1, "Resource cards, settlements, cities, roads, dev cards, VP"),
        (1, "can_build() / do_build() / do_trade() helpers; 7-card discard rule"),
        (0, "strategy.R — Strategy interface + implementations"),
        (1, "Each strategy is a named list of functions: choose_initial_placement, choose_road_placement, choose_action"),
        (0, "game.R — Single game loop (reverse snake draft → turns → win check)"),
        (0, "simulation.R — Monte Carlo runner: run_simulation(n_games, seed)"),
        (0, "analysis.R — ggplot2 charts + chi-squared significance test"),
    ],
)


# ══════════════════════════════════════════════════════════════════════════════
# Slide 8 — Game Loop
# ══════════════════════════════════════════════════════════════════════════════
add_bullet_slide(
    "Game Loop (game.R)",
    [
        (0, "Initial placement — reverse snake draft"),
        (1, "P1 → P2 → P3 → P4 → P4 → P3 → P2 → P1"),
        (1, "Second settlement grants 1 of each adjacent resource to start"),
        (0, "Each turn: Roll → Robber/Production → Trade → Build"),
        (1, "Roll 7: discard rule (>7 cards) + robber targets the leading player"),
        (1, "Production: settlements yield 1 resource, cities yield 2"),
        (1, "Trade: bank 4:1 or port rates (3:1 general / 2:1 specific)"),
        (0, "Win condition: first player to reach 10 VP on their turn"),
        (1, "Stalemate safeguard: game ends after 200 turns (recorded as NA winner)"),
        (0, "Special VP bonuses tracked each turn"),
        (1, "Longest Road (≥ 5 segments) → 2 VP"),
        (1, "Largest Army (≥ 3 knights) → 2 VP"),
    ],
)


# ══════════════════════════════════════════════════════════════════════════════
# Slide 9 — Simplifications vs. Full Catan
# ══════════════════════════════════════════════════════════════════════════════
add_table_slide(
    "Simplifications vs. Full Catan Rules",
    ["Full Rule", "Simulation Simplification", "Impact on Results"],
    [
        ["Player-to-player trading",
         "Omitted — bank/port trading only",
         "Low: all strategies affected equally"],
        ["Longest Road",
         "Tracked; 2 VP at ≥5 road segments",
         "Faithful to rules"],
        ["Largest Army",
         "Tracked; 2 VP at ≥3 knights",
         "Faithful to rules"],
        ["Dev card variety",
         "Knights + VP cards; Progress cards stubbed",
         "Minor: removes Road Building / Monopoly edge cases"],
        ["Robber targeting",
         "Always targets the leading player (most VP)",
         "Deterministic; slightly penalises front-runners"],
        ["Board geometry",
         "Intersection IDs enumerated for simulation; not pixel-perfect",
         "Structural relationships preserved"],
    ],
    col_widths=[Inches(2.8), Inches(4.4), Inches(5.0)],
)


# ══════════════════════════════════════════════════════════════════════════════
# Slide 10 — How to Run
# ══════════════════════════════════════════════════════════════════════════════
slide = prs.slides.add_slide(BLANK)
bg(slide, OFF_WHITE)
rect(slide, 0, 0, SLIDE_W, Inches(1.1), fill_color=MID_GREEN)
textbox(slide, "How to Run the Simulation",
        Inches(0.4), Inches(0.12), Inches(12.5), Inches(0.9),
        font_size=Pt(32), bold=True, color=CREAM)

# code block background
rect(slide, Inches(0.4), Inches(1.3), Inches(8.5), Inches(3.2),
     fill_color=DARK_GREEN,
     line_color=LIGHT_GREEN, line_width=Pt(1.5))

code = (
    'source("R/simulation.R")\n\n'
    'results <- run_simulation(\n'
    '    n_games = 1000,\n'
    '    seed    = 42\n'
    ')\n\n'
    'source("R/analysis.R")\n'
    'plot_win_rates(results)'
)
textbox(slide, code,
        Inches(0.7), Inches(1.45), Inches(8.0), Inches(2.9),
        font_size=Pt(17), color=LIGHT_GREEN, bold=False)

# side notes
notes = [
    ("Output", "results/simulation_results.csv"),
    ("Charts", "Win rate bar chart with 95% CIs\nVP distribution violin/boxplot"),
    ("Stats",  "χ² test on win-count table\nTarget: p < 0.05"),
    ("Time",   "< 60 seconds for 1,000 games"),
]
for i, (label, detail) in enumerate(notes):
    top = Inches(1.35) + i * Inches(1.45)
    rect(slide, Inches(9.2), top, Inches(3.7), Inches(1.25),
         fill_color=CREAM, line_color=RGBColor(0xCC,0xCC,0xBB), line_width=Pt(0.75))
    textbox(slide, label,
            Inches(9.35), top + Inches(0.08), Inches(3.4), Inches(0.4),
            font_size=Pt(14), bold=True, color=DARK_GREEN)
    textbox(slide, detail,
            Inches(9.35), top + Inches(0.45), Inches(3.4), Inches(0.7),
            font_size=Pt(13), color=DARK_TEXT)


# ══════════════════════════════════════════════════════════════════════════════
# Slides 11–13 — Results placeholders
# ══════════════════════════════════════════════════════════════════════════════

def placeholder_slide(title_text, chart_label, note_text):
    slide = prs.slides.add_slide(BLANK)
    bg(slide, OFF_WHITE)
    rect(slide, 0, 0, SLIDE_W, Inches(1.1), fill_color=MID_GREEN)
    textbox(slide, title_text,
            Inches(0.4), Inches(0.12), Inches(12.5), Inches(0.9),
            font_size=Pt(32), bold=True, color=CREAM)
    # Chart placeholder box
    rect(slide, Inches(0.5), Inches(1.25), Inches(12.3), Inches(5.5),
         fill_color=RGBColor(0xE8, 0xF2, 0xE0),
         line_color=MID_GREEN, line_width=Pt(2))
    textbox(slide, chart_label,
            Inches(0.5), Inches(3.5), Inches(12.3), Inches(0.8),
            font_size=Pt(22), bold=True, color=MID_GREEN, align=PP_ALIGN.CENTER)
    textbox(slide, note_text,
            Inches(0.5), Inches(4.4), Inches(12.3), Inches(0.6),
            font_size=Pt(15), color=RGBColor(0x55,0x55,0x55), align=PP_ALIGN.CENTER,
            italic=True)
    return slide

placeholder_slide(
    "Results: Win Rates by Strategy",
    "[ Bar chart: win rate per strategy with 95% confidence intervals ]",
    "Source: results/simulation_results.csv  ·  n = 1,000 games  ·  seed = 42",
)
placeholder_slide(
    "Results: VP Distribution at Game End",
    "[ Violin / boxplot: final VP per strategy across all games ]",
    "Source: results/simulation_results.csv  ·  n = 1,000 games  ·  seed = 42",
)
placeholder_slide(
    "Statistical Analysis",
    "[ χ² test output: observed vs. expected win counts, p-value, conclusion ]",
    "Success criterion: p < 0.05  ·  null hypothesis: all strategies win equally often",
)


# ══════════════════════════════════════════════════════════════════════════════
# Slide 14 — Summary
# ══════════════════════════════════════════════════════════════════════════════
slide = prs.slides.add_slide(BLANK)
bg(slide, OFF_WHITE)
rect(slide, 0, 0, SLIDE_W, Inches(1.1), fill_color=DARK_GREEN)
textbox(slide, "Summary",
        Inches(0.4), Inches(0.12), Inches(10), Inches(0.9),
        font_size=Pt(32), bold=True, color=CREAM)

# Sticker — right side
sticker_h2 = Inches(3.0)
sticker_w2 = sticker_h2 * (200 / 231)
slide.shapes.add_picture(_STICKER_PNG,
                         SLIDE_W - sticker_w2 - Inches(0.4),
                         Inches(1.2),
                         sticker_w2, sticker_h2)

# Bullet content (left 9.5")
bullets_sum = [
    (0, "Sheep strategy loses — the numbers prove it"),
    (1, "Win rate significantly lower than balanced (p < 0.05) across 1,000 games"),
    (0, "Why: wool is structurally weak as a primary resource"),
    (1, "Cities need ore + grain, not wool"),
    (1, "Wool is abundant; the 2:1 port advantage is marginal"),
    (0, "Balanced strategy dominates"),
    (1, "Maximise pips, diversity, and ore/grain for cities"),
    (0, "Reproducible · Fast · Open source"),
]
txb = slide.shapes.add_textbox(Inches(0.5), Inches(1.3), Inches(9.0), Inches(5.4))
tf  = txb.text_frame
tf.word_wrap = True
for i, (indent, text) in enumerate(bullets_sum):
    p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
    run = p.add_run()
    if indent == 0:
        run.text = "▸  " + text
        run.font.size  = Pt(20)
        run.font.bold  = True
        run.font.color.rgb = DARK_GREEN
    else:
        run.text = "     •  " + text
        run.font.size  = Pt(17)
        run.font.color.rgb = DARK_TEXT

# GitHub URL + label below sticker
textbox(slide, REPO_URL,
        SLIDE_W - sticker_w2 - Inches(0.4),
        Inches(1.2) + sticker_h2 + Inches(0.15),
        sticker_w2, Inches(0.45),
        font_size=Pt(13), color=MID_GREEN, align=PP_ALIGN.CENTER, bold=True)


# ══════════════════════════════════════════════════════════════════════════════
# Slide 15 — Acknowledgements
# ══════════════════════════════════════════════════════════════════════════════
slide = prs.slides.add_slide(BLANK)
bg(slide, DARK_GREEN)
rect(slide, 0, 0, SLIDE_W, Inches(1.1), fill_color=MID_GREEN)
textbox(slide, "Acknowledgements",
        Inches(0.4), Inches(0.12), Inches(12.5), Inches(0.9),
        font_size=Pt(32), bold=True, color=CREAM)

# Card — Goof Troop
rect(slide, Inches(0.4), Inches(1.3), Inches(5.9), Inches(5.7),
     fill_color=RGBColor(0x22, 0x4A, 0x22),
     line_color=LIGHT_GREEN, line_width=Pt(1.5))
textbox(slide, "The Goof Troop",
        Inches(0.55), Inches(1.45), Inches(5.6), Inches(0.6),
        font_size=Pt(22), bold=True, color=LIGHT_GREEN)
goof_text = (
    "For countless hours of Catan, "
    "heated port disputes, questionable trades, "
    "and the kind of chaotic gameplay that makes "
    "statistical analysis both necessary and deeply "
    "personal.\n\n"
    "This project exists because of you."
)
textbox(slide, goof_text,
        Inches(0.55), Inches(2.15), Inches(5.6), Inches(4.5),
        font_size=Pt(17), color=CREAM)

# Card — Mark
rect(slide, Inches(6.85), Inches(1.3), Inches(5.9), Inches(5.7),
     fill_color=RGBColor(0x22, 0x4A, 0x22),
     line_color=LIGHT_GREEN, line_width=Pt(1.5))
textbox(slide, "Mark",
        Inches(7.0), Inches(1.45), Inches(5.6), Inches(0.6),
        font_size=Pt(22), bold=True, color=LIGHT_GREEN)
mark_text = (
    "For his unwavering commitment to the sheep strategy "
    "in the face of all evidence, logic, and repeated defeat.\n\n"
    "Without Mark's baaad decisions, this project "
    "would never have been born.\n\n"
    "The data is dedicated to him."
)
textbox(slide, mark_text,
        Inches(7.0), Inches(2.15), Inches(5.6), Inches(4.5),
        font_size=Pt(17), color=CREAM)

# Divider line between cards
rect(slide, Inches(6.55), Inches(1.5), Inches(0.05), Inches(5.2),
     fill_color=LIGHT_GREEN)


# ══════════════════════════════════════════════════════════════════════════════
# Save
# ══════════════════════════════════════════════════════════════════════════════
out = "C:/Users/amyou/Documents/GitHub/baaad-strategy/baaad-strategy.pptx"
prs.save(out)
print(f"Saved: {out}")
