import sys, copy, os
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from lxml import etree

sys.stdout.reconfigure(encoding='utf-8')

PPTX_PATH = "baaad-strategy.pptx"
prs = Presentation(PPTX_PATH)

# Content area shared across slides
CONTENT_LEFT   = Inches(0.5)
CONTENT_TOP    = Inches(1.25)
CONTENT_WIDTH  = Inches(12.3)
CONTENT_HEIGHT = Inches(5.5)

# ---------------------------------------------------------------------------
# Helper: remove placeholder text boxes from a slide by name
# ---------------------------------------------------------------------------
def remove_shapes_by_name(slide, *names):
    sp_tree = slide.shapes._spTree
    for shape in list(slide.shapes):
        if shape.name in names:
            sp_tree.remove(shape.element)

# ---------------------------------------------------------------------------
# Helper: add image centred/fitted inside the content area
# ---------------------------------------------------------------------------
def add_image_to_content_area(slide, img_path):
    slide.shapes.add_picture(
        img_path,
        left=CONTENT_LEFT,
        top=CONTENT_TOP,
        width=CONTENT_WIDTH,
        height=CONTENT_HEIGHT,
    )

# ---------------------------------------------------------------------------
# Helper: add a new slide matching existing header style
# ---------------------------------------------------------------------------
def add_results_slide(prs, title_text, img_path, insert_index):
    blank_layout = prs.slides[0].slide_layout
    new_slide = prs.slides.add_slide(blank_layout)

    # Copy header rectangle from slide 2
    for shape in prs.slides[1].shapes:
        if shape.name == "Rectangle 1":
            new_slide.shapes._spTree.insert(2, copy.deepcopy(shape.element))
            break

    # Copy content background rectangle from slide 2
    for shape in prs.slides[1].shapes:
        if shape.name == "Rectangle 3":
            new_slide.shapes._spTree.insert(3, copy.deepcopy(shape.element))
            break

    # Title text box
    tb = new_slide.shapes.add_textbox(Inches(0.4), Inches(0.12), Inches(12.5), Inches(0.9))
    tf = tb.text_frame
    run = tf.paragraphs[0].add_run()
    run.text = title_text
    run.font.bold = True
    run.font.size = Pt(28)
    run.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)

    # Image
    new_slide.shapes.add_picture(img_path, CONTENT_LEFT, CONTENT_TOP, CONTENT_WIDTH, CONTENT_HEIGHT)

    # Move to correct position
    xml_slides = prs.slides._sldIdLst
    entries = list(xml_slides)
    target = entries[-1]
    xml_slides.remove(target)
    xml_slides.insert(insert_index, target)

    return new_slide

# ---------------------------------------------------------------------------
# Slide 11 — Win Rates: replace placeholder with image
# ---------------------------------------------------------------------------
slide11 = prs.slides[10]
remove_shapes_by_name(slide11, "TextBox 4", "TextBox 5")
add_image_to_content_area(slide11, os.path.abspath("figures/win_rates.png"))
print("Slide 11 updated with win_rates.png")

# ---------------------------------------------------------------------------
# Slide 12 — VP Distribution: replace placeholder with image
# ---------------------------------------------------------------------------
slide12 = prs.slides[11]
remove_shapes_by_name(slide12, "TextBox 4", "TextBox 5")
add_image_to_content_area(slide12, os.path.abspath("figures/vp_distribution.png"))
print("Slide 12 updated with vp_distribution.png")

# ---------------------------------------------------------------------------
# New slides for vp_breakdown and game_length
# Insert after slide 12 (index 12), before representative game (index 13)
# Insert high index first, then lower, to preserve order
# ---------------------------------------------------------------------------
add_results_slide(prs, "Results: Game Length Distribution", os.path.abspath("figures/game_length.png"), 13)
print("New slide added: game_length.png at position 13")

add_results_slide(prs, "Results: VP Breakdown by Strategy", os.path.abspath("figures/vp_breakdown.png"), 13)
print("New slide added: vp_breakdown.png at position 13")

# ---------------------------------------------------------------------------
# Save and verify
# ---------------------------------------------------------------------------
prs.save(PPTX_PATH)
print(f"\nSaved: {PPTX_PATH}")

prs2 = Presentation(PPTX_PATH)
print(f"Total slides: {len(prs2.slides)}")
for i, slide in enumerate(prs2.slides):
    title = ''
    for shape in slide.shapes:
        if shape.has_text_frame:
            t = shape.text_frame.text.strip()
            if t and len(t) < 80:
                title = t
                break
    imgs = ' [IMAGE]' if any(s.shape_type == 13 for s in slide.shapes) else ''
    print(f"  Slide {i+1}: {title}{imgs}")
