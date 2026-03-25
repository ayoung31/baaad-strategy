import sys, copy, os
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from lxml import etree

sys.stdout.reconfigure(encoding='utf-8')

PPTX_PATH = "baaad-strategy.pptx"
prs = Presentation(PPTX_PATH)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def set_cell_text(cell, text, bold=False, font_size=None):
    """Replace all text in a table cell with a single paragraph."""
    tf = cell.text_frame
    tf.clear()
    para = tf.paragraphs[0]
    run = para.add_run()
    run.text = text
    run.font.bold = bold
    if font_size:
        run.font.size = Pt(font_size)


def find_textbox(slide, name):
    for shape in slide.shapes:
        if shape.name == name:
            return shape
    return None


def replace_text_in_shape(shape, old, new):
    """Replace occurrences of old with new in every run of a text frame."""
    if not shape.has_text_frame:
        return
    for para in shape.text_frame.paragraphs:
        for run in para.runs:
            if old in run.text:
                run.text = run.text.replace(old, new)


def get_header_fill(prs):
    """Return the XML fill element from the header rectangle of slide 2."""
    rect = find_textbox(prs.slides[1], "Rectangle 1")
    if rect is None:
        return None
    return rect.element.spPr.solidFill if rect.element.spPr is not None else None


def add_slide_with_header(prs, title_text):
    """Add a new blank slide matching the presentation's header style."""
    blank_layout = prs.slides[0].slide_layout  # Blank layout
    new_slide = prs.slides.add_slide(blank_layout)

    # --- Header rectangle ---
    # Copy the rectangle element from an existing slide to match style exactly
    template_rect = None
    for shape in prs.slides[1].shapes:
        if shape.name == "Rectangle 1":
            template_rect = shape
            break

    if template_rect is not None:
        rect_el = copy.deepcopy(template_rect.element)
        new_slide.shapes._spTree.insert(2, rect_el)

    # --- Title text box ---
    txBox = new_slide.shapes.add_textbox(
        Inches(0.4), Inches(0.12), Inches(12.5), Inches(0.9)
    )
    tf = txBox.text_frame
    tf.word_wrap = False
    para = tf.paragraphs[0]
    run = para.add_run()
    run.text = title_text
    run.font.bold = True
    run.font.size = Pt(28)
    run.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)

    return new_slide


def insert_slide_at(prs, slide, index):
    """Move a slide (already added at end) to a specific index."""
    xml_slides = prs.slides._sldIdLst
    # The slide is currently last — move it
    entries = list(xml_slides)
    target = entries[-1]          # the just-added slide
    xml_slides.remove(target)
    xml_slides.insert(index, target)


# ---------------------------------------------------------------------------
# SLIDE 3 — Strategy table
# ---------------------------------------------------------------------------
slide3 = prs.slides[2]
table = None
for shape in slide3.shapes:
    if shape.shape_type == 19:
        table = shape.table
        break

if table:
    # Header row already correct; update data rows
    # Row 1 = balanced
    set_cell_text(table.cell(1, 0), "balanced", bold=True)
    set_cell_text(table.cell(1, 1),
        "pip_sum + 1×distinct_resources\n(both picks use same formula; diversity naturally avoids duplication)")
    set_cell_text(table.cell(1, 2),
        "Routes to highest-diversity open intersection; road built only when it opens a new settlement spot")
    set_cell_text(table.cell(1, 3),
        "City → Settlement → Dev card → Road\nFlexible; city is top priority throughout")

    # Row 2 = sheep
    set_cell_text(table.cell(2, 0), "sheep", bold=True)
    set_cell_text(table.cell(2, 1),
        "wool_pips×2 + total_pips×0.5\n2nd pick: infra guard (ensure lumber/brick) + Wool port bonus (+100)")
    set_cell_text(table.cell(2, 2),
        "Routes to 2:1 Wool port until secured;\nthen best remaining wool spot")
    set_cell_text(table.cell(2, 3),
        "Dev card → Settlement → City → Road\nBets on Largest Army VP; city deliberately deprioritised")

    # Row 3 = ore_grain
    set_cell_text(table.cell(3, 0), "ore_grain", bold=True)
    set_cell_text(table.cell(3, 1),
        "(ore+grain)_pips×2 + total_pips×0.5\n2nd pick: infra guard + Ore/Grain port bonus (+50)")
    set_cell_text(table.cell(3, 2),
        "Routes to 2:1 Ore or Grain port until secured;\nthen best ore+grain spot")
    set_cell_text(table.cell(3, 3),
        "City → Settlement (capped at 4) → Dev card → Road\nCity upgrades are the entire strategy")

print("Slide 3 updated")

# ---------------------------------------------------------------------------
# SLIDE 8 — Architecture: strategy interface fix + add visualize_board.R
# ---------------------------------------------------------------------------
slide8 = prs.slides[7]
for shape in slide8.shapes:
    if shape.name == "TextBox 4" and shape.has_text_frame:
        for para in shape.text_frame.paragraphs:
            for run in para.runs:
                # Fix strategy interface: add choose_second_placement
                if "choose_in" in run.text and "choose_road" in run.text:
                    run.text = run.text.replace(
                        "choose_initial_placement, choose_road_placement, choose_action",
                        "choose_initial_placement, choose_second_placement, choose_road_placement, choose_action"
                    )
                # Fix module count in architecture description if present
                if "simulation.R — Monte Carlo runner" in run.text:
                    run.text = run.text.replace(
                        "simulation.R — Monte Carlo runner: run_simulation(n_games, seed)",
                        "simulation.R — Monte Carlo runner: run_simulation(n_games, strategies, seed)"
                    )
                # Add visualize_board.R after analysis.R mention
                if "analysis.R — ggplot2 charts" in run.text:
                    run.text = run.text.replace(
                        "analysis.R — ggplot2 charts + chi-squared significance test",
                        "analysis.R — ggplot2 charts + chi-squared significance test\n▸  visualize_board.R — Board & game-state rendering (plot_board, plot_game_state)"
                    )
        # Also update the title from "6 R Modules" to "7 R Modules"
for shape in slide8.shapes:
    if shape.name == "TextBox 2" and shape.has_text_frame:
        for para in shape.text_frame.paragraphs:
            for run in para.runs:
                if "6 R Modules" in run.text:
                    run.text = run.text.replace("6 R Modules", "7 R Modules")

print("Slide 8 updated")

# ---------------------------------------------------------------------------
# SLIDE 9 — Game loop: fix stalemate turn count
# ---------------------------------------------------------------------------
slide9 = prs.slides[8]
for shape in slide9.shapes:
    if shape.has_text_frame:
        for para in shape.text_frame.paragraphs:
            for run in para.runs:
                if "200 turns" in run.text:
                    run.text = run.text.replace("200 turns", "500 turns")

print("Slide 9 updated")

# ---------------------------------------------------------------------------
# SLIDE 10 — Simplifications: fix dev card row
# ---------------------------------------------------------------------------
slide10 = prs.slides[9]
for shape in slide10.shapes:
    if shape.shape_type == 19:
        tbl = shape.table
        for r in range(tbl._tbl.tr_lst.__len__()):
            row = tbl.rows[r]
            for c in range(len(row.cells)):
                cell = row.cells[c]
                txt = cell.text_frame.text
                if "Progress cards stubbed" in txt:
                    set_cell_text(cell,
                        "Full 25-card deck: 14 Knights + 5 VP cards + 2 each of Year of Plenty, Monopoly, Road Building")
                if "Knights + VP cards" in txt:
                    set_cell_text(cell, "All dev card types implemented and played by strategies")

print("Slide 10 updated")

# ---------------------------------------------------------------------------
# SLIDE 12 — Title fix (stalemate note already correct)
# SLIDE 13 — (VP distribution, no changes needed)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# NEW SLIDE — Representative game: Seed 99 (insert before slide 14 = Stats)
# ---------------------------------------------------------------------------
new_slide = add_slide_with_header(prs, "A Representative Game: ore_grain Wins (Seed 99)")

# Content background rectangle (match other content slides)
template_bg = None
for shape in prs.slides[1].shapes:
    if shape.name == "Rectangle 3":
        template_bg = shape
        break
if template_bg is not None:
    bg_el = copy.deepcopy(template_bg.element)
    new_slide.shapes._spTree.insert(2, bg_el)

# Add image (left 55% of slide)
img_path = os.path.abspath("figures/game_seed_99.png")
pic = new_slide.shapes.add_picture(
    img_path,
    left=Inches(0.3), top=Inches(1.2),
    width=Inches(7.4), height=Inches(6.1)
)

# Add bullets text box (right side)
txBox = new_slide.shapes.add_textbox(
    Inches(7.85), Inches(1.3), Inches(5.25), Inches(6.0)
)
tf = txBox.text_frame
tf.word_wrap = True

bullets = [
    ("Winner: ore_grain in 60 turns", True, 14),
    ("Fastest ore_grain win in our 37-seed sample — a board where ore and grain placement aligned well from the start", False, 12),
    ("", False, 12),
    ("ore_grain: 1 settlement, 3 cities", True, 14),
    ("Cities double ore/grain output, funding further cities — the compounding VP loop playing out at full speed", False, 12),
    ("", False, 12),
    ("sheep: 3 settlements, 0 cities", True, 14),
    ("Accumulated wool but could not convert it to ore/grain; stuck near starting VP with no upgrade path", False, 12),
    ("", False, 12),
    ("balanced: 4 settlements, 0 cities", True, 14),
    ("Diversified production but on this board couldn't reach city resources before ore_grain closed out", False, 12),
    ("", False, 12),
    ("Key takeaway", True, 14),
    ("When ore_grain secures strong ore/grain placement, it wins decisively. Sheep demonstrates the starvation failure mode regardless of board.", False, 12),
]

first = True
for (text, bold, size) in bullets:
    if first:
        para = tf.paragraphs[0]
        first = False
    else:
        para = tf.add_paragraph()
    if text == "":
        para.text = ""
        continue
    run = para.add_run()
    run.text = text
    run.font.bold = bold
    run.font.size = Pt(size)
    if bold:
        run.font.color.rgb = RGBColor(0x1A, 0x1A, 0x1A)
    else:
        run.font.color.rgb = RGBColor(0x33, 0x33, 0x33)

# Move the new slide to position 13 (0-indexed = before old slide 14 = Statistical Analysis)
insert_slide_at(prs, new_slide, 13)

print("New results slide added")

# ---------------------------------------------------------------------------
# SLIDE 15 (was 15, now 16) — Summary: add ore_grain
# ---------------------------------------------------------------------------
# After inserting a slide, indices shift by 1
slide15 = prs.slides[15]  # was slide 15, now 16 after insertion
for shape in slide15.shapes:
    if shape.name == "TextBox 4" and shape.has_text_frame:
        for para in shape.text_frame.paragraphs:
            for run in para.runs:
                if "Balanced strategy dominates" in run.text:
                    run.text = run.text.replace(
                        "Balanced strategy dominates",
                        "Two strategies outperform sheep"
                    )
                if "Maximise pips, diversity, and ore/grain for cities" in run.text:
                    run.text = run.text.replace(
                        "Maximise pips, diversity, and ore/grain for cities",
                        "Balanced: pip diversity + city focus; consistent on any board\nOre_grain: ore/grain dominance + city compounding; wins fast when placement aligns"
                    )

print("Slide 15 (summary) updated")

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------
prs.save(PPTX_PATH)
print(f"\nSaved: {PPTX_PATH}")
