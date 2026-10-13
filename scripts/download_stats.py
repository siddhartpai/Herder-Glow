#!/usr/bin/env python3
"""Adds today's total release downloads to downloads.csv and draws downloads.svg.

Usage: download_stats.py <owner/repo> <output dir>
Reads GITHUB_TOKEN from the environment when it is set.
"""
import csv
import datetime
import json
import os
import sys
import urllib.request

repo, out = sys.argv[1], sys.argv[2]
request = urllib.request.Request(f"https://api.github.com/repos/{repo}/releases?per_page=100")
if os.environ.get("GITHUB_TOKEN"):
    request.add_header("Authorization", f"Bearer {os.environ['GITHUB_TOKEN']}")
with urllib.request.urlopen(request) as response:
    releases = json.load(response)
total = sum(asset["download_count"] for release in releases for asset in release["assets"])

# One row per day; a second run on the same day replaces that day's row.
path = os.path.join(out, "downloads.csv")
rows = []
if os.path.exists(path):
    with open(path) as f:
        rows = [(r["date"], int(r["downloads"])) for r in csv.DictReader(f)]
today = datetime.date.today().isoformat()
rows = [r for r in rows if r[0] != today] + [(today, total)]
with open(path, "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["date", "downloads"])
    writer.writerows(rows)

# Line chart of the running total, in the site's dark style.
width, height, left, right, top, bottom = 720, 300, 56, 24, 48, 40
plot_w, plot_h = width - left - right, height - top - bottom
peak = max(max(n for _, n in rows), 1)
def x(i): return left + (plot_w * i / (len(rows) - 1) if len(rows) > 1 else plot_w / 2)
def y(n): return top + plot_h - plot_h * n / peak
points = " ".join(f"{x(i):.1f},{y(n):.1f}" for i, (_, n) in enumerate(rows))
area = f"{x(0):.1f},{top + plot_h} {points} {x(len(rows) - 1):.1f},{top + plot_h}"
font = "font-family='-apple-system,Segoe UI,Helvetica,Arial,sans-serif'"
svg = f"""<svg xmlns='http://www.w3.org/2000/svg' width='{width}' height='{height}' viewBox='0 0 {width} {height}'>
<rect width='100%' height='100%' rx='14' fill='#0d0e14'/>
<text x='{left}' y='30' fill='#f4f4f6' font-size='16' font-weight='700' {font}>Herdr-Glow downloads</text>
<text x='{width - right}' y='30' fill='#38db8c' font-size='16' font-weight='700' text-anchor='end' {font}>{total} total</text>
<line x1='{left}' y1='{top + plot_h}' x2='{width - right}' y2='{top + plot_h}' stroke='#ffffff22'/>
<text x='{left - 8}' y='{top + 4}' fill='#ffffff88' font-size='11' text-anchor='end' {font}>{peak}</text>
<text x='{left - 8}' y='{top + plot_h + 4}' fill='#ffffff88' font-size='11' text-anchor='end' {font}>0</text>
<text x='{left}' y='{height - 14}' fill='#ffffff88' font-size='11' {font}>{rows[0][0]}</text>
<text x='{width - right}' y='{height - 14}' fill='#ffffff88' font-size='11' text-anchor='end' {font}>{rows[-1][0]}</text>
<polygon points='{area}' fill='#428fff22'/>
<polyline points='{points}' fill='none' stroke='#428fff' stroke-width='2.5' stroke-linejoin='round'/>
<circle cx='{x(len(rows) - 1):.1f}' cy='{y(rows[-1][1]):.1f}' r='4' fill='#428fff'/>
</svg>
"""
with open(os.path.join(out, "downloads.svg"), "w") as f:
    f.write(svg)
print(f"{today}: {total} downloads")
