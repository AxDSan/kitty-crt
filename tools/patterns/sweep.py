#!/usr/bin/env python3
"""Bright blocks sweeping across the screen: the trail behind each one is the phosphor afterglow."""
import sys
import time

ESC = "\x1b"
sys.stdout.write(f"{ESC}[2J{ESC}[?25l")
for row in (4, 8, 12):
    sys.stdout.write(f"{ESC}[{row};3H{ESC}[97mrow {row}: the trail behind the block is the afterglow of the phosphor{ESC}[0m")
x = 0
while True:
    for row, step in ((6, 2), (10, 4), (14, 1)):
        sys.stdout.write(f"{ESC}[{row};1H" + " " * 110)
        sys.stdout.write(f"{ESC}[{row};{(x * step) % 100 + 1}H{ESC}[97m████████{ESC}[0m")
    sys.stdout.flush()
    x += 1
    time.sleep(0.03)
