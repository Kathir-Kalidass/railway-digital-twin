#!/usr/bin/env python3
"""Generate high-quality figures for the conference paper."""

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, Circle, Polygon, FancyArrowPatch, RegularPolygon, Ellipse
from matplotlib.colors import LinearSegmentedColormap
import numpy as np
import os

OUTDIR = os.path.dirname(os.path.abspath(__file__))
os.makedirs(OUTDIR, exist_ok=True)

# Color palette
DARK_BLUE = "#1B3A6B"
ACCENT_BLUE = "#2E75B6"
LIGHT_BLUE = "#BDD7EE"
VERY_LIGHT_BLUE = "#DEEBF7"
DARK_GRAY = "#262626"
RED = "#C0392B"
GREEN = "#1A854B"
ORANGE = "#E67E22"
TEAL = "#17A2A8"
PURPLE = "#8E44AD"
WHITE = "#FFFFFF"
GOLD = "#D4AC0D"

# ============================================================
# FIG 1: fig_architecture.png
# ============================================================
fig, ax = plt.subplots(figsize=(14, 6.5))
ax.set_xlim(0, 15)
ax.set_ylim(0, 7)
ax.axis("off")
ax.set_title("CNN Architecture for Railway Track Defect Detection",
             fontsize=15, fontweight="bold", color=DARK_BLUE, pad=12)

def draw_block(ax, x, y, w, h, text, color=ACCENT_BLUE, text_color=WHITE, fontsize=9, edge_color=None):
    if edge_color is None:
        edge_color = DARK_BLUE
    rect = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.06,rounding_size=0.15",
                           facecolor=color, edgecolor=edge_color, linewidth=1.5, zorder=3)
    ax.add_patch(rect)
    ax.text(x + w/2, y + h/2, text, ha="center", va="center",
            color=text_color, fontsize=fontsize, fontweight="bold", zorder=4)

def draw_arrow(ax, x1, y1, x2, y2, color=DARK_GRAY):
    ax.annotate("", xy=(x2, y1), xytext=(x1, y1),
                arrowprops=dict(arrowstyle="->", color=color, lw=2), zorder=2)

# Input block
draw_block(ax, 0.2, 3.8, 1.5, 1.5, "Input\n200x200x3\nRGB Image", DARK_BLUE, WHITE, 10)

# Conv blocks
conv_data = [
    ("Conv Block 1\n32 filters, 3x3\nReLU + MaxPool", ACCENT_BLUE),
    ("Conv Block 2\n64 filters, 3x3\nReLU + MaxPool", "#2471A3"),
    ("Conv Block 3\n128 filters, 3x3\nReLU + MaxPool", "#3498DB"),
    ("Conv Block 4\n256 filters, 3x3\nReLU + MaxPool", "#5DADE2"),
]
x_start = 2.1
for i, (label, color) in enumerate(conv_data):
    draw_block(ax, x_start + i*2.8, 4.0, 2.5, 1.2, label, color, WHITE, 9)
    # Feature map size
    fm_x = x_start + i*2.8 + 0.1
    fm_y = 3.2
    ax.add_patch(plt.Rectangle((fm_x, fm_y), 2.3, 0.5, facecolor=color, edgecolor=DARK_BLUE, linewidth=1, alpha=0.8, zorder=2))
    fm_texts = ["200x200x3", "98x98x32", "48x48x64", "22x22x128"]
    ax.text(fm_x + 1.15, fm_y + 0.25, fm_texts[i], ha="center", va="center",
            fontsize=8, color=WHITE, fontweight="bold", zorder=4)
    if i < 3:
        draw_arrow(ax, x_start + i*2.8 + 2.5, 4.6, x_start + (i+1)*2.8, 4.6)

# Final conv arrow
draw_arrow(ax, x_start + 3*2.8 + 2.5, 4.6, 12.3, 4.6)

# Global Average Pooling
draw_block(ax, 12.3, 4.2, 1.8, 1.2, "Global Avg\nPooling", TEAL, WHITE, 10)
draw_arrow(ax, 13.2, 4.6, 13.2, 5.6)

# FC + Dropout
draw_block(ax, 12.3, 5.7, 1.8, 0.9, "FC: 512 units\nDropout 0.5", ORANGE, WHITE, 10)
draw_arrow(ax, 13.2, 5.7, 13.2, 6.8)

# Output
draw_block(ax, 12.3, 6.8, 1.8, 0.8, "Sigmoid\nBinary Output", GREEN, WHITE, 10)

# Labels (a), (b), (c)
ax.text(0.95, 3.3, "(a) Input", ha="center", fontsize=9, color=DARK_GRAY, style="italic")
ax.text(13.2, 3.6, "(b) Feature\nExtraction", ha="center", fontsize=9, color=DARK_GRAY, style="italic")
ax.text(13.2, 6.0, "(c) Classification", ha="center", fontsize=9, color=DARK_GRAY, style="italic")

# Info boxes
info1 = FancyBboxPatch((0.2, 0.15), 7.0, 0.9, boxstyle="round,pad=0.05",
                        facecolor=VERY_LIGHT_BLUE, edgecolor=ACCENT_BLUE, linewidth=1.5, zorder=2)
ax.add_patch(info1)
ax.text(3.7, 0.6, "Training: Adam optimiser  |  LR = 0.001  |  50 epochs  |  "
        "Early stopping  |  Data augmentation (rotation, flip, brightness adjustment)",
        ha="center", va="center", fontsize=9, color=DARK_BLUE, zorder=3)

info2 = FancyBboxPatch((7.6, 0.15), 7.4, 0.9, boxstyle="round,pad=0.05",
                        facecolor="#FEF9E7", edgecolor=GOLD, linewidth=1.5, zorder=2)
ax.add_patch(info2)
ax.text(11.3, 0.6, "Loss: Weighted Cross-Entropy  |  w_FN = 10, w_FP = 1  |  "
        "Asymmetric cost function penalising false negatives tenfold",
        ha="center", va="center", fontsize=9, color="#7D6608", zorder=3)

plt.tight_layout()
plt.savefig(os.path.join(OUTDIR, "fig_architecture.png"), dpi=200, bbox_inches="tight", facecolor="white")
plt.close()
print("Created: fig_architecture.png")

# ============================================================
# FIG 2: fig_robustness.png
# ============================================================
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))

conditions = ["Normal\nLighting", "Poor\nLighting", "Rust /\nDirt", "Shadow\nOcclusion", "Combined\nAdverse"]
accuracy = [93.2, 87.1, 85.6, 81.3, 78.4]
fnr = [8.5, 15.3, 17.2, 21.4, 22.7]

# Accuracy chart
colors_acc = [GREEN, "#27AE60", ORANGE, "#D35400", RED]
bars1 = ax1.bar(conditions, accuracy, color=colors_acc, edgecolor=DARK_BLUE, linewidth=1.2, width=0.55)
ax1.set_ylim(0, 105)
ax1.set_ylabel("Accuracy (%)", fontsize=12, fontweight="bold")
ax1.set_title("(a) Accuracy Under Environmental Conditions", fontsize=13, fontweight="bold", color=DARK_BLUE)
ax1.axhline(y=90, color=RED, linestyle="--", linewidth=1.5, alpha=0.7)
ax1.text(4.3, 92, "90% Safety\nThreshold", fontsize=9, color=RED, ha="right", fontweight="bold")
ax1.axhspan(85, 105, alpha=0.06, color=GREEN)
ax1.axhspan(0, 85, alpha=0.04, color=RED)
for bar, val in zip(bars1, accuracy):
    ax1.text(bar.get_x() + bar.get_width()/2, val + 1.5, f"{val}%",
             ha="center", fontsize=11, fontweight="bold", color=DARK_GRAY)
ax1.tick_params(axis="x", labelsize=10)
ax1.tick_params(axis="y", labelsize=10)

# FNR chart
colors_fnr = ["#3498DB", "#E67E22", "#E67E22", RED, RED]
bars2 = ax2.bar(conditions, fnr, color=colors_fnr, edgecolor=DARK_BLUE, linewidth=1.2, width=0.55)
ax2.set_ylim(0, 30)
ax2.set_ylabel("False Negative Rate (%)", fontsize=12, fontweight="bold")
ax2.set_title("(b) False Negative Rate -- The Critical Safety Metric", fontsize=13, fontweight="bold", color=DARK_BLUE)
ax2.axhline(y=5, color=GREEN, linestyle="--", linewidth=2, alpha=0.8)
ax2.text(0.3, 6, "5%\nTarget", fontsize=9, color=GREEN, fontweight="bold")
ax2.axhline(y=10, color=ORANGE, linestyle="--", linewidth=1.5, alpha=0.6)
ax2.text(0.3, 11, "10%", fontsize=8, color=ORANGE)
ax2.axhspan(5, 30, alpha=0.05, color=RED)
for bar, val in zip(bars2, fnr):
    ax2.text(bar.get_x() + bar.get_width()/2, val + 0.7, f"{val}%",
             ha="center", fontsize=11, fontweight="bold", color=DARK_GRAY)
ax2.tick_params(axis="x", labelsize=10)
ax2.tick_params(axis="y", labelsize=10)

fig.text(0.5, 0.01,
         "Key Finding: FNR increases 2.7x under combined adverse conditions (8.5% -> 22.7%), "
         "demonstrating that accuracy alone is an insufficient safety metric.",
         ha="center", va="center", fontsize=10, color=RED, fontweight="bold",
         bbox=dict(boxstyle="round,pad=0.5", facecolor="#FADBD8", edgecolor=RED, linewidth=1.5))

fig.suptitle("Robustness Analysis: Model Performance Degradation Under Adverse Environmental Conditions",
             fontsize=14, fontweight="bold", color=DARK_BLUE, y=0.97)
plt.tight_layout(rect=[0, 0.04, 1, 0.95])
plt.savefig(os.path.join(OUTDIR, "fig_robustness.png"), dpi=200, bbox_inches="tight", facecolor="white")
plt.close()
print("Created: fig_robustness.png")

# ============================================================
# FIG 3: fig_gradcam.png
# ============================================================
fig, axes = plt.subplots(1, 3, figsize=(16, 5.5))
fig.suptitle("Grad-CAM Explainability: Attention Region Analysis for Railway Defect Detection",
             fontsize=14, fontweight="bold", color=DARK_BLUE, y=1.02)

rail_x_left = 2.5
rail_x_right = 8.5
rail_top_y = 7.5
rail_bot_y = 5.0

# Helper to draw base rail scene
def draw_base_scene(ax):
    ax.set_xlim(0, 11)
    ax.set_ylim(0, 11)
    ax.set_aspect("equal")
    # Rail
    ax.fill_between([rail_x_left, rail_x_right], rail_bot_y, rail_top_y,
                     color="#A0A0A0", edgecolor=DARK_BLUE, linewidth=2.5, zorder=2)
    ax.fill_between([rail_x_left, rail_x_right], 6.8, rail_top_y,
                     color="#C0C0C0", edgecolor="none", alpha=0.5, zorder=2)
    # Ballast
    np.random.seed(42)
    for bx in np.linspace(0.5, 10.5, 25):
        ax.add_patch(Circle((bx, 2.5 + np.random.rand() * 0.8), 0.18,
                             facecolor="#B8A888", edgecolor="none", alpha=0.6, zorder=1))
    ax.fill_between([0, 11], 0, 4.2, color="#D4C4A8", edgecolor="none", alpha=0.25, zorder=0)

# Panel 1: Input image
ax = axes[0]
draw_base_scene(ax)
ax.plot([5.2, 5.8], [6.8, 5.8], color=RED, linewidth=4, solid_capstyle="round", zorder=3)
ax.scatter([5.5], [6.3], color=RED, s=250, marker="*", zorder=5, edgecolors=DARK_BLUE, linewidths=0.5)
ax.set_title("(a) Input Image\n(Defect at rail center)", fontsize=12, fontweight="bold", color=DARK_BLUE)
ax.axis("off")

# Panel 2: Correct detection
ax = axes[1]
draw_base_scene(ax)
for size, alpha, c in [(3.2, 0.12, "blue"), (2.3, 0.22, "cyan"), (1.5, 0.38, "lime"), (0.8, 0.55, "yellow")]:
    ax.add_patch(Ellipse((5.5, 6.3), size, size * 0.7, angle=-35, facecolor=c, alpha=alpha, edgecolor="none", zorder=3))
ax.plot([5.2, 5.8], [6.8, 5.8], color=RED, linewidth=2, linestyle="--", alpha=0.8, zorder=4)
ax.set_title("(b) Grad-CAM: Correct Detection\n(Heatmap on crack region)", fontsize=12,
             fontweight="bold", color=GREEN)
ax.axis("off")

# Panel 3: Missed detection
ax = axes[2]
draw_base_scene(ax)
# Wrong heatmap on ballast
for size, alpha, c in [(3.0, 0.12, "blue"), (2.1, 0.22, "cyan"), (1.3, 0.38, "lime"), (0.7, 0.55, "yellow")]:
    ax.add_patch(Ellipse((3.8, 3.2), size, size * 0.8, angle=15, facecolor=c, alpha=alpha, edgecolor="none", zorder=3))
# Actual crack (unattended)
ax.plot([5.2, 5.8], [6.8, 5.8], color=RED, linewidth=2.5, linestyle="--", alpha=0.9, zorder=4)
ax.scatter([5.5], [6.3], color=RED, s=220, marker="X", zorder=5, edgecolors=DARK_BLUE, linewidths=0.5)
ax.annotate("Missed!\n(FN)", xy=(5.5, 6.3), xytext=(8.0, 9.0),
            arrowprops=dict(arrowstyle="->", color=RED, lw=2),
            fontsize=10, color=RED, fontweight="bold",
            bbox=dict(boxstyle="round,pad=0.3", facecolor="#FADBD8", edgecolor=RED))
ax.set_title("(c) Grad-CAM: Missed Detection\n(Model attended to ballast, not crack)",
             fontsize=12, fontweight="bold", color=RED)
ax.axis("off")

# Shared colorbar legend on the right
ax_leg = fig.add_axes([0.93, 0.15, 0.012, 0.55])
gradient = np.linspace(0, 1, 256).reshape(-1, 1)
ax_leg.imshow(gradient, aspect="auto", cmap="jet", extent=[0, 1, 0, 1])
ax_leg.set_xticks([])
ax_leg.set_yticks([0, 0.5, 1])
ax_leg.set_yticklabels(["Low", "Medium", "High"], fontsize=8)
ax_leg.set_title("Attention\nIntensity", fontsize=8, fontweight="bold")
ax_leg.yaxis.tick_right()

plt.tight_layout(rect=[0, 0, 0.93, 0.97])
plt.savefig(os.path.join(OUTDIR, "fig_gradcam.png"), dpi=200, bbox_inches="tight", facecolor="white")
plt.close()
print("Created: fig_gradcam.png")

# ============================================================
# FIG 4: fig_framework.png
# ============================================================
fig, ax = plt.subplots(figsize=(15, 7))
ax.set_xlim(0, 16)
ax.set_ylim(0, 8)
ax.axis("off")
ax.set_title("Proposed Human-in-the-Loop Framework for AI-Assisted Railway Track Inspection",
             fontsize=15, fontweight="bold", color=DARK_BLUE, pad=12)

def draw_flow_box(ax, x, y, w, h, text, color, text_color=WHITE, fontsize=9):
    rect = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.08,rounding_size=0.2",
                           facecolor=color, edgecolor=DARK_BLUE, linewidth=2, zorder=3)
    ax.add_patch(rect)
    ax.text(x + w/2, y + h/2, text, ha="center", va="center",
            color=text_color, fontsize=fontsize, fontweight="bold", zorder=4)

def draw_decision(ax, x, y, size, text):
    hexagon = RegularPolygon((x, y), 6, radius=size, orientation=np.pi/6,
                              facecolor=ORANGE, edgecolor=DARK_BLUE, linewidth=2, zorder=3)
    ax.add_patch(hexagon)
    ax.text(x, y, text, ha="center", va="center", fontsize=8.5, fontweight="bold", color=WHITE, zorder=4)

# Step 1: Input
draw_flow_box(ax, 0.2, 3.3, 1.8, 1.4, "Camera /\nDrone /\nTRC Scan", DARK_BLUE, WHITE, 10)
ax.text(1.1, 3.0, "(1) Data Capture", ha="center", fontsize=8, color=DARK_GRAY, style="italic")

# Step 2: AI Detection
draw_flow_box(ax, 3.0, 3.3, 1.8, 1.4, "AI Defect\nDetection\n(CNN)", ACCENT_BLUE, WHITE, 10)
ax.text(3.9, 3.0, "(2) AI Inference", ha="center", fontsize=8, color=DARK_GRAY, style="italic")

# Step 3: Explainability
draw_flow_box(ax, 5.8, 3.3, 1.8, 1.4, "Grad-CAM\nExplainability\nLayer", TEAL, WHITE, 10)
ax.text(6.7, 3.0, "(3) Explanation", ha="center", fontsize=8, color=DARK_GRAY, style="italic")

# Step 4: Decision
draw_decision(ax, 8.9, 4.0, 0.75, "Confidence\n> Threshold?")

# Arrows between steps
for x1, x2 in [(2.0, 3.0), (4.8, 5.8), (7.6, 8.15)]:
    ax.annotate("", xy=(x2, 4.0), xytext=(x1, 4.0),
                arrowprops=dict(arrowstyle="->", color=DARK_GRAY, lw=2), zorder=2)

# YES branch -> Inspector Review
draw_flow_box(ax, 10.5, 5.5, 2.4, 1.5, "Human Inspector\nReview with\nGrad-CAM Overlay", GREEN, WHITE, 10)
ax.annotate("YES\n(High conf.)", xy=(10.5, 5.5), xytext=(9.05, 4.7),
            fontsize=9, fontweight="bold", color=GREEN, ha="center",
            arrowprops=dict(arrowstyle="->", color=GREEN, lw=2))

# NO branch -> Escalation
draw_flow_box(ax, 10.5, 1.2, 2.4, 1.5, "Mandatory Manual\nInspection\n(Escalation)", RED, WHITE, 10)
ax.annotate("NO\n(Low conf.)", xy=(10.5, 1.2), xytext=(9.05, 2.8),
            fontsize=9, fontweight="bold", color=RED, ha="center",
            arrowprops=dict(arrowstyle="->", color=RED, lw=2))

# Arrows from decision diamond
ax.annotate("", xy=(10.5, 6.2), xytext=(9.4, 4.35), arrowprops=dict(arrowstyle="->", color=GREEN, lw=2.5))
ax.annotate("", xy=(10.5, 1.9), xytext=(9.4, 3.65), arrowprops=dict(arrowstyle="->", color=RED, lw=2.5))

# Step 5: Maintenance Decision
draw_flow_box(ax, 13.7, 5.5, 2.1, 1.4, "Maintenance\nDecision &\nAuthorization", "#2471A3", WHITE, 10)
ax.annotate("", xy=(13.7, 6.2), xytext=(12.9, 6.25), arrowprops=dict(arrowstyle="->", color=DARK_GRAY, lw=2))

# Step 6: Audit Log
draw_flow_box(ax, 13.7, 1.8, 2.1, 1.3, "Audit Log &\nCompliance\nRecord", PURPLE, WHITE, 10)
ax.annotate("", xy=(13.7, 2.45), xytext=(12.9, 2.35), arrowprops=dict(arrowstyle="->", color=DARK_GRAY, lw=2))

# Inspector override arrow (curved)
ax.annotate("Override /\nDisagree", xy=(4.0, 3.0), xytext=(6.5, 1.0),
            arrowprops=dict(arrowstyle="->", color=ORANGE, lw=1.8, connectionstyle="arc3,rad=-0.3"),
            fontsize=9, color=ORANGE, fontweight="bold",
            bbox=dict(boxstyle="round,pad=0.2", facecolor="#FEF9E7", edgecolor=ORANGE))

# Bottom legend
legend_items = [
    (GREEN, "Human-in-the-loop", "Inspector always has override authority"),
    (ORANGE, "Confidence routing", "Low confidence -> mandatory manual review"),
    (PURPLE, "Audit trail", "All decisions logged for accountability"),
    (DARK_BLUE, "RDSO alignment", "Maintenance per established procedures"),
]
for i, (color, label, desc) in enumerate(legend_items):
    x_pos = 0.3 + i * 4.0
    ax.add_patch(plt.Rectangle((x_pos, 0.15), 0.9, 0.4, facecolor=color, edgecolor=DARK_BLUE, linewidth=1.5, zorder=3))
    ax.text(x_pos + 0.45, 0.35, label, ha="center", va="center", fontsize=8, fontweight="bold", color=WHITE, zorder=4)
    ax.text(x_pos + 1.0, 0.35, desc, ha="left", va="center", fontsize=8, color=DARK_GRAY, zorder=4)

plt.tight_layout()
plt.savefig(os.path.join(OUTDIR, "fig_framework.png"), dpi=200, bbox_inches="tight", facecolor="white")
plt.close()
print("Created: fig_framework.png")

# ============================================================
# FIG 5: fig_taxonomy.png
# ============================================================
fig, ax = plt.subplots(figsize=(13, 7))
ax.set_xlim(0, 14)
ax.set_ylim(0, 8)
ax.axis("off")
ax.set_title("Responsible AI Principles for Railway Track Defect Detection",
             fontsize=15, fontweight="bold", color=DARK_BLUE, pad=12)

# Central node
center_circle = Circle((7, 4.0), 1.0, color=DARK_BLUE, zorder=5)
ax.add_patch(center_circle)
ax.text(7, 4.3, "Responsible", ha="center", va="center", fontsize=12,
        fontweight="bold", color=WHITE, zorder=6)
ax.text(7, 3.8, "AI Principles", ha="center", va="center", fontsize=12,
        fontweight="bold", color=WHITE, zorder=6)
ax.text(7, 3.1, "Railway Inspection Domain", ha="center", va="center", fontsize=8.5,
        color="#BDD7EE", zorder=6, style="italic")

# Outer ring
angles = np.linspace(0, 2 * np.pi, 7)[:-1]
ring_r = 3.0
for angle in angles:
    x = 7 + ring_r * np.cos(angle)
    y = 4.0 + ring_r * np.sin(angle)
    ax.plot([7, x], [4.0, y], color=LIGHT_BLUE, linewidth=3, zorder=1, alpha=0.7)

principles = [
    ("Safety &\nRobustness", ACCENT_BLUE, "FNR < 5%\nEnvironmental testing\nField validation"),
    ("Explainability", TEAL, "Grad-CAM heatmaps\nInspector verification\nModel debugging"),
    ("Accountability", ORANGE, "Clear roles defined\nRDSO alignment\nAudit trail"),
    ("Human Oversight", GREEN, "Mandatory review\nOverride authority\nEngineering judgement"),
    ("Fairness &\nInclusion", PURPLE, "Cross-region testing\nDefect-type coverage\nBias evaluation"),
    ("Privacy &\nSecurity", RED, "Access controls\nAdversarial defense\nData governance"),
]

node_r = 1.4
for i, (label, color, desc) in enumerate(principles):
    angle = angles[i]
    cx = 7 + (ring_r + node_r + 0.3) * np.cos(angle)
    cy = 4.0 + (ring_r + node_r + 0.3) * np.sin(angle)
    circle = Circle((cx, cy), node_r, color=color, zorder=3, alpha=0.92)
    ax.add_patch(circle)
    ax.text(cx, cy + 0.15, label, ha="center", va="center", fontsize=10,
            fontweight="bold", color=WHITE, zorder=4)
    ax.text(cx, cy - 0.55, desc, ha="center", va="center", fontsize=8,
            color=DARK_GRAY, zorder=4)
    # connecting line
    ring_x = 7 + ring_r * np.cos(angle)
    ring_y = 4.0 + ring_r * np.sin(angle)
    nd_x = cx - node_r * np.cos(angle)
    nd_y = cy - node_r * np.sin(angle)
    ax.plot([ring_x, nd_x], [ring_y, nd_y], color=LIGHT_BLUE, linewidth=2, zorder=2)

# Bottom annotation
box = FancyBboxPatch((0.3, 0.08), 13.4, 0.75, boxstyle="round,pad=0.03",
                      facecolor=LIGHT_BLUE, edgecolor=DARK_BLUE, linewidth=2, zorder=2)
ax.add_patch(box)
ax.text(7, 0.45,
        "All six principles must be explicitly addressed in AI deployment for safety-critical railway inspection. "
        "Neglecting any principle creates unacceptable risk where a single missed defect can cause derailment.",
        ha="center", va="center", fontsize=10, color=DARK_BLUE, fontweight="bold", zorder=3)

plt.tight_layout()
plt.savefig(os.path.join(OUTDIR, "fig_taxonomy.png"), dpi=200, bbox_inches="tight", facecolor="white")
plt.close()
print("Created: fig_taxonomy.png")

print("\nAll figures generated successfully!")
