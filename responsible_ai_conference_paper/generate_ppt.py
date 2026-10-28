#!/usr/bin/env python3
"""Generate compact conference presentation PPT with images."""

from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
import os

# ---- Colors ----
DARK_BLUE = RGBColor(0x1B, 0x3A, 0x6B)
ACCENT_BLUE = RGBColor(0x2E, 0x75, 0xB6)
LIGHT_BLUE = RGBColor(0xBD, 0xD7, 0xEE)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
DARK_GRAY = RGBColor(0x26, 0x26, 0x26)
RED = RGBColor(0xC0, 0x39, 0x2B)
GREEN = RGBColor(0x1A, 0x85, 0x4B)
ORANGE = RGBColor(0xE6, 0x7E, 0x22)
TEAL = RGBColor(0x17, 0xA2, 0xA8)
PURPLE = RGBColor(0x8E, 0x44, 0xAD)
GOLD = RGBColor(0xD4, 0xAC, 0x0D)

SLIDE_W = Inches(13.33)
SLIDE_H = Inches(7.5)
IMG_DIR = os.path.dirname(os.path.abspath(__file__))

prs = Presentation()
prs.slide_width = SLIDE_W
prs.slide_height = SLIDE_H

def blank_slide():
    return prs.slides.add_slide(prs.slide_layouts[6])

def add_header_bar(slide, title, subtitle=""):
    bar = slide.shapes.add_shape(1, Inches(0), Inches(0), SLIDE_W, Inches(1.0))
    bar.fill.solid()
    bar.fill.fore_color.rgb = DARK_BLUE
    bar.line.fill.background()
    tf = bar.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    run = p.add_run()
    run.text = title
    run.font.size = Pt(28)
    run.font.bold = True
    run.font.color.rgb = WHITE
    if subtitle:
        p2 = tf.add_paragraph()
        run2 = p2.add_run()
        run2.text = subtitle
        run2.font.size = Pt(14)
        run2.font.color.rgb = LIGHT_BLUE

def add_footer(slide, text="CEG, Anna University | Responsible AI 2026"):
    box = slide.shapes.add_textbox(Inches(0.5), Inches(7.1), Inches(12.3), Inches(0.3))
    tf = box.text_frame
    p = tf.paragraphs[0]
    run = p.add_run()
    run.text = text
    run.font.size = Pt(10)
    run.font.color.rgb = ACCENT_BLUE
    p.alignment = PP_ALIGN.CENTER

def bullet_box(slide, left, top, width, height, items, font_size=14, spacing=6, color=DARK_GRAY, bold_first=False):
    box = slide.shapes.add_textbox(left, top, width, height)
    tf = box.text_frame
    tf.word_wrap = True
    for i, item in enumerate(items):
        if i == 0:
            p = tf.paragraphs[0]
        else:
            p = tf.add_paragraph()
        p.space_before = Pt(spacing)
        p.space_after = Pt(2)
        run = p.add_run()
        run.text = item
        run.font.size = Pt(font_size)
        run.font.color.rgb = color
        if bold_first and i == 0:
            run.font.bold = True
    return box

def section_slide(title, subtitle=""):
    slide = blank_slide()
    bar = slide.shapes.add_shape(1, Inches(0), Inches(0), SLIDE_W, Inches(2.8))
    bar.fill.solid()
    bar.fill.fore_color.rgb = DARK_BLUE
    bar.line.fill.background()
    tf = bar.text_frame
    p = tf.paragraphs[0]
    run = p.add_run()
    run.text = title
    run.font.size = Pt(44)
    run.font.bold = True
    run.font.color.rgb = WHITE
    p.alignment = PP_ALIGN.CENTER
    if subtitle:
        p2 = tf.add_paragraph()
        run2 = p2.add_run()
        run2.text = subtitle
        run2.font.size = Pt(20)
        run2.font.color.rgb = LIGHT_BLUE
        p2.alignment = PP_ALIGN.CENTER
    add_footer(slide)
    return slide

# ============================================================
# SLIDE 1: Title
# ============================================================
slide = blank_slide()
bar = slide.shapes.add_shape(1, Inches(0), Inches(0), SLIDE_W, Inches(3.5))
bar.fill.solid()
bar.fill.fore_color.rgb = DARK_BLUE
bar.line.fill.background()
tf = bar.text_frame
tf.word_wrap = True
p = tf.paragraphs[0]
run = p.add_run()
run.text = "AI-Based Railway Track Defect Detection in India"
run.font.size = Pt(38)
run.font.bold = True
run.font.color.rgb = WHITE
p.alignment = PP_ALIGN.CENTER

p2 = tf.add_paragraph()
run2 = p2.add_run()
run2.text = "False Negatives, Safety Assurance and Human Accountability"
run2.font.size = Pt(24)
run2.font.color.rgb = LIGHT_BLUE
p2.alignment = PP_ALIGN.CENTER

p3 = tf.add_paragraph()
run3 = p3.add_run()
run3.text = "Responsible AI Case Study"
run3.font.size = Pt(16)
run3.font.color.rgb = GOLD
p3.alignment = PP_ALIGN.CENTER

# Authors
box = slide.shapes.add_textbox(Inches(0.5), Inches(3.9), Inches(12.3), Inches(1.2))
tf2 = box.text_frame
tf2.word_wrap = True
p = tf2.paragraphs[0]
run = p.add_run()
run.text = "Jivetesh  |  Kathir Kalidass B  |  Dhinesh Babu C M  |  Paril T"
run.font.size = Pt(18)
run.font.color.rgb = DARK_GRAY
p.alignment = PP_ALIGN.CENTER

p2 = tf2.add_paragraph()
run2 = p2.add_run()
run2.text = "College of Engineering, Guindy (CEG), Anna University, Chennai -- 600025, India"
run2.font.size = Pt(14)
run2.font.color.rgb = ACCENT_BLUE
p2.alignment = PP_ALIGN.CENTER
add_footer(slide)

# ============================================================
# SLIDE 2: Agenda
# ============================================================
slide = blank_slide()
add_header_bar(slide, "Agenda")
bullet_box(slide, Inches(1.0), Inches(1.3), Inches(11.3), Inches(5.5), [
    "1.  Domain Context -- Indian Railway Safety Challenges",
    "2.  Why AI? -- Opportunities, Limitations & Critical Distinctions",
    "3.  Technical Approach -- CNN Architecture for Defect Detection",
    "4.  Results -- Performance, False Negative Rate & Robustness",
    "5.  Explainability -- Grad-CAM Visualizations",
    "6.  Framework -- Human-in-the-Loop Pipeline",
    "7.  Responsible AI Principles -- Safety, Accountability, Governance",
    "8.  Recommendations & Conclusion",
], font_size=16, spacing=10)
add_footer(slide)

# ============================================================
# SLIDE 3: Background
# ============================================================
slide = blank_slide()
add_header_bar(slide, "Indian Railways -- A Safety-Critical Domain", "68,000+ km of track | 23M+ daily passengers | Safety cannot be compromised")
bullet_box(slide, Inches(0.5), Inches(1.2), Inches(6.5), Inches(5.8), [
    "Network Scale:",
    "  • 68,000+ route-kilometres across diverse geography",
    "  • 13,000+ passenger trains, 9,000+ freight trains daily",
    "  • 23+ million passengers daily",
    "",
    "Inspection Challenges:",
    "  • TRCs, patrolling -- effective but infrequent",
    "  • Human fatigue & visibility affect quality",
    "  • Continuous monitoring impossible at this scale",
    "",
    "AI Opportunity:",
    "  • High-frequency surface defect monitoring",
    "  • Flag sections for priority human inspection",
], font_size=14, spacing=6)

bullet_box(slide, Inches(7.3), Inches(1.2), Inches(5.5), Inches(5.8), [
    "Critical Distinction:",
    "  SURFACE defects (detectable by AI):",
    "    - Transverse cracks, head checks, squats",
    "    - Shelling, surface corrosion, wear",
    "",
    "  INTERNAL flaws (require NDT):",
    "    - Hydrogen cracks, gauge corner cracking",
    "    - Weld defects, internal fractures",
    "",
    "  RDSO T-53 (2020): Ultrasonic testing",
    "  remains mandatory for compliance",
    "",
    "  AI visual inspection = DECISION-SUPPORT",
    "  tool, not a replacement for NDT",
], font_size=14, spacing=6, color=DARK_GRAY)
add_footer(slide)

# ============================================================
# SLIDE 4: Technical Approach + Architecture Figure
# ============================================================
slide = blank_slide()
add_header_bar(slide, "Technical Approach -- CNN Architecture", "Binary classification: Defective vs Normal rail surface")

# Architecture image on the right
if os.path.exists(os.path.join(IMG_DIR, "fig_architecture.png")):
    slide.shapes.add_picture(os.path.join(IMG_DIR, "fig_architecture.png"),
                              Inches(6.8), Inches(1.2), Inches(6.0), Inches(4.8))

bullet_box(slide, Inches(0.4), Inches(1.3), Inches(6.3), Inches(5.5), [
    "Model: Convolutional Neural Network (CNN)",
    "  • 4 Conv blocks: 32 -> 64 -> 128 -> 256 filters",
    "  • Global Average Pooling + FC(512) + Dropout(0.5)",
    "  • Binary output (Sigmoid)",
    "",
    "Input: 200x200 RGB rail surface images",
    "",
    "Training:",
    "  • Adam optimiser, LR = 0.001, 50 epochs",
    "  • Augmentation: rotation, flip, brightness",
    "  • Early stopping on validation loss",
    "",
    "Explainability: Grad-CAM attention heatmaps",
    "",
    "Key Innovation: Weighted loss (w_FN=10, w_FP=1)",
    " penalises missed defects 10x more than false alarms",
], font_size=13, spacing=5)
add_footer(slide)

# ============================================================
# SLIDE 5: Results + Robustness Figure
# ============================================================
slide = blank_slide()
add_header_bar(slide, "Key Results -- Performance & Robustness")

# Robustness image
if os.path.exists(os.path.join(IMG_DIR, "fig_robustness.png")):
    slide.shapes.add_picture(os.path.join(IMG_DIR, "fig_robustness.png"),
                              Inches(6.5), Inches(1.2), Inches(6.4), Inches(3.2))

bullet_box(slide, Inches(0.4), Inches(1.3), Inches(6.0), Inches(5.5), [
    "Performance (Ideal Conditions):",
    "  Accuracy:   93.2%",
    "  Precision:  94.1%",
    "  Recall:     91.5%",
    "  F1-Score:   92.8%",
    "  FNR:        8.5%  ⚠",
    "",
    "Robustness Findings:",
    "  • FNR increases 2.7x under adverse conditions",
    "  • Shadow occlusion causes largest FNR jump",
    "  • Accuracy alone is an unsafe metric",
    "",
    "⚠  1 in 12 defects missed in ideal conditions",
    "⚠  1 in 4 defects missed in worst-case field conditions",
], font_size=13, spacing=5)
add_footer(slide)

# ============================================================
# SLIDE 6: Explainability + Grad-CAM Figure
# ============================================================
slide = blank_slide()
add_header_bar(slide, "Explainability -- Grad-CAM Visualizations", "Understanding why the model makes its decisions")

if os.path.exists(os.path.join(IMG_DIR, "fig_gradcam.png")):
    slide.shapes.add_picture(os.path.join(IMG_DIR, "fig_gradcam.png"),
                              Inches(4.5), Inches(1.2), Inches(8.4), Inches(3.0))

bullet_box(slide, Inches(0.4), Inches(1.3), Inches(4.0), Inches(5.5), [
    "Grad-CAM highlights regions",
    "the model attended to:",
    "",
    "(a) Correct Detection:",
    "  Heatmap on crack region",
    "  → Model learned correctly",
    "",
    "(b) Missed Detection:",
    "  Heatmap on ballast (wrong!)",
    "  → Spurious correlation learned",
    "",
    "(c) False Positive:",
    "  Heatmap on shadow pattern",
    "  → Texture confusion",
    "",
    "Inspectors use heatmaps to",
    "verify or override AI decisions",
], font_size=13, spacing=5)
add_footer(slide)

# ============================================================
# SLIDE 7: Framework + Framework Figure
# ============================================================
slide = blank_slide()
add_header_bar(slide, "Proposed Human-in-the-Loop Framework", "AI supports inspectors -- never replaces them")

if os.path.exists(os.path.join(IMG_DIR, "fig_framework.png")):
    slide.shapes.add_picture(os.path.join(IMG_DIR, "fig_framework.png"),
                              Inches(0.3), Inches(1.2), Inches(12.7), Inches(3.8))

bullet_box(slide, Inches(0.4), Inches(5.1), Inches(12.5), Inches(1.8), [
    "Seven-stage pipeline: Image Capture -> AI Detection -> Grad-CAM -> Confidence Routing -> Inspector Review -> Maintenance -> Audit Log",
    "Low-confidence classifications trigger mandatory manual inspection. Inspectors always retain override authority.",
], font_size=13, spacing=4, color=ACCENT_BLUE)
add_footer(slide)

# ============================================================
# SLIDE 8: RAI Principles + Taxonomy Figure
# ============================================================
slide = blank_slide()
add_header_bar(slide, "Responsible AI Principles for Railway Inspection")

if os.path.exists(os.path.join(IMG_DIR, "fig_taxonomy.png")):
    slide.shapes.add_picture(os.path.join(IMG_DIR, "fig_taxonomy.png"),
                              Inches(0.3), Inches(1.15), Inches(8.5), Inches(4.2))

bullet_box(slide, Inches(9.0), Inches(1.2), Inches(4.0), Inches(5.5), [
    "Six Core Principles:",
    "",
    "1. Safety & Robustness",
    "   FNR < 5%, field testing",
    "",
    "2. Explainability",
    "   Grad-CAM for trust & debugging",
    "",
    "3. Accountability",
    "   Clear roles, RDSO alignment",
    "",
    "4. Human Oversight",
    "   Mandatory review, override right",
    "",
    "5. Fairness & Inclusion",
    "   Cross-region, defect-type testing",
    "",
    "6. Privacy & Security",
    "   Access control, audit trail",
], font_size=12, spacing=4)
add_footer(slide)

# ============================================================
# SLIDE 9: Recommendations
# ============================================================
slide = blank_slide()
add_header_bar(slide, "Key Recommendations for Responsible Deployment")

# Two columns
bullet_box(slide, Inches(0.4), Inches(1.2), Inches(6.0), Inches(5.8), [
    "Do NOT deploy standalone",
    "    -- operate within existing governance",
    "",
    "Report FALSE NEGATIVE RATE",
    "    -- not just overall accuracy",
    "",
    "Maintain ultrasonic testing",
    "    -- AI cannot replace NDT",
    "",
    "Confidence-based escalation",
    "    -- low confidence = mandatory review",
], font_size=15, spacing=10)

bullet_box(slide, Inches(6.8), Inches(1.2), Inches(6.0), Inches(5.8), [
    "Explicit accountability chains",
    "    -- who reviews, authorises, is responsible",
    "",
    "Environmental robustness testing",
    "    -- validate per railway division",
    "",
    "Explainability from design phase",
    "    -- not retrofitted for compliance",
    "",
    "The goal: AI that augments inspector",
    "capability while maintaining the safety",
    "assurance passengers depend upon.",
], font_size=15, spacing=10)
add_footer(slide)

# ============================================================
# SLIDE 10: Thank You / Q&A
# ============================================================
slide = blank_slide()
bar = slide.shapes.add_shape(1, Inches(0), Inches(0), SLIDE_W, Inches(3.0))
bar.fill.solid()
bar.fill.fore_color.rgb = DARK_BLUE
bar.line.fill.background()
tf = bar.text_frame
p = tf.paragraphs[0]
run = p.add_run()
run.text = "Thank You"
run.font.size = Pt(56)
run.font.bold = True
run.font.color.rgb = WHITE
p.alignment = PP_ALIGN.CENTER

p2 = tf.add_paragraph()
run2 = p2.add_run()
run2.text = "Questions & Discussion"
run2.font.size = Pt(24)
run2.font.color.rgb = LIGHT_BLUE
p2.alignment = PP_ALIGN.CENTER

box = slide.shapes.add_textbox(Inches(1), Inches(4.0), Inches(11.3), Inches(2.5))
tf2 = box.text_frame
tf2.word_wrap = True
p = tf2.paragraphs[0]
run = p.add_run()
run.text = "Jivetesh  |  Kathir Kalidass B  |  Dhinesh Babu C M  |  Paril T"
run.font.size = Pt(18)
run.font.color.rgb = DARK_GRAY
p.alignment = PP_ALIGN.CENTER

p2 = tf2.add_paragraph()
run2 = p2.add_run()
run2.text = "College of Engineering, Guindy, Anna University, Chennai -- 600025, India"
run2.font.size = Pt(14)
run2.font.color.rgb = ACCENT_BLUE
p2.alignment = PP_ALIGN.CENTER
add_footer(slide)

# Save
out = os.path.join(IMG_DIR, "TEAM_4_RESPONSIBLE_AI_Railway_Track_defect.pptx")
prs.save(out)
print(f"Saved: {out}")
print(f"Total slides: {len(prs.slides)}")
