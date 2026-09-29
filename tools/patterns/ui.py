#!/usr/bin/env python3
"""A static, omp-like screen used for the README images: a prompt box, tool calls, code, colour ramps."""
import os
import sys
import time

ESC = "\x1b"
time.sleep(float(os.environ.get("UI_DELAY", "0")))  # lets a caller resize the window before anything is printed


def sgr(text, fg=None, bg=None, bold=False):
    out = ""
    if bold:
        out += f"{ESC}[1m"
    if fg:
        out += f"{ESC}[38;2;{fg[0]};{fg[1]};{fg[2]}m"
    if bg:
        out += f"{ESC}[48;2;{bg[0]};{bg[1]};{bg[2]}m"
    return out + text + f"{ESC}[0m"


AMBER = (255, 176, 0)
lines = [
    sgr("╭─ omp · oh-my-pi ─────────────────────────────────────────────────╮", AMBER, bold=True),
    sgr("│", AMBER) + sgr(" > make omp look like a CRT: phosphor glow, scanlines, curvature   ", (205, 205, 205)) + sgr("│", AMBER),
    sgr("╰──────────────────────────────────────────────────────────────────╯", AMBER),
    "",
    sgr("✔ read ", (120, 220, 120)) + sgr("shaders/retro-crt.slang", (180, 180, 180)) + sgr("   (600 lines)", (95, 95, 95)),
    sgr("● edit ", (240, 200, 60)) + sgr("bin/crt", (180, 180, 180)) + sgr("   +38 -12", (95, 95, 95)),
    sgr("✘ bash ", (240, 90, 90)) + sgr("slangc: error 20001: unexpected identifier", (180, 180, 180)),
    "",
    "The quick brown fox jumps over the lazy dog. 0123456789 {}[]()<>=+-*/\\|~^",
    'fn main() { println!("hello, phosphor"); }   Il1|O0o  #include <stdio.h>',
    "",
    "gray ramp:  " + "".join(sgr(" ", bg=(v, v, v)) for v in range(0, 256, 8)),
    "red ramp:   " + "".join(sgr(" ", bg=(v, 0, 0)) for v in range(0, 256, 8)),
    "green ramp: " + "".join(sgr(" ", bg=(0, v, 0)) for v in range(0, 256, 8)),
    "blue ramp:  " + "".join(sgr(" ", bg=(0, 0, v)) for v in range(0, 256, 8)),
    "shades:     " + "░▒▓█ " * 12,
    "",
    sgr(" INVERSE AMBER ", (0, 0, 0), AMBER) + " " + sgr(" INVERSE WHITE ", (0, 0, 0), (255, 255, 255)) + " " + sgr(" BLUE PANEL ", (255, 255, 255), (0, 0, 180)),
    sgr("─" * 68, (90, 90, 90)),
    sgr("aj@fedora", AMBER) + sgr(":", (150, 150, 150)) + sgr("~/kitty-crt", (100, 150, 255)) + sgr("$ ", (150, 150, 150)) + "█",
]
sys.stdout.write(f"{ESC}[2J{ESC}[H{ESC}[?25l" + "\n".join(lines) + "\n")
sys.stdout.flush()
time.sleep(int(sys.argv[1]) if len(sys.argv) > 1 else 600)
