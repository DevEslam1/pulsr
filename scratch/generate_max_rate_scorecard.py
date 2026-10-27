"""Generate the Pulsr max-rate scorecard workbook.

Single source of truth for the scores used in
docs/MAX_RATE_FEATURE_DOSSIER_2026-10-26.md.
"""

from __future__ import annotations

from collections import OrderedDict
from pathlib import Path

from openpyxl import Workbook
from openpyxl.chart import BarChart, Reference
from openpyxl.formatting.rule import ColorScaleRule
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.table import Table, TableStyleInfo

OUT = Path("docs/pulsr_max_rate_scorecard_2026-10-26.xlsx")

# id, domain, feature, Q, F, X, effort, impact, wave, top optimisation, top function
ROWS = [
    (1, "A. Playback & DSP", "Playback core", 7.6, 8.6, 7.4, "L", 5, 1,
     "Single-writer queue actor; frame-true position", "Beat/key automix 2.0 + cross-device listening sessions"),
    (2, "A. Playback & DSP", "Native DSP engine", 9.2, 8.8, 8.2, "L", 5, 2,
     "Multi-rate graph, SIMD, per-stage CPU cost model", "Multichannel, DSD512, linear-phase FIR, head-tracked binaural"),
    (3, "A. Playback & DSP", "EQ & room correction", 8.5, 8.3, 8.0, "M", 4, 2,
     "One EQ engine; RTA overlay; 2 s AutoEq import", "Target-curve library, hearing-profile EQ, per-device recall"),
    (4, "A. Playback & DSP", "Bit-perfect output & DAC", 8.4, 8.0, 7.6, "L", 4, 2,
     "Per-track rate follow; UAC2 hardware volume; hotplug FSM", "DSD512/768k, codec badge, chain-of-custody certificate"),
    (5, "A. Playback & DSP", "Playback intelligence", 7.8, 8.4, 7.6, "M", 4, 2,
     "R128 true-peak loudness; confident automix", "Radio-from-track, energy-arc Auto-DJ, mood shuffle"),
    (6, "A. Playback & DSP", "Lyrics & karaoke", 8.0, 7.6, 7.6, "M", 4, 2,
     "Parser fuzz; ±20 ms sync; 60 fps active line", "Word-level timing, duet + pitch scoring, studio mode"),
    (7, "A. Playback & DSP", "Themes & visualizers", 8.3, 7.4, 8.4, "M", 3, 2,
     "Token-only themes; 9x3x2 goldens; 8 ms GPU budget", "Theme gallery, Milkdrop presets, per-track visuals"),
    (8, "B. Library & discovery", "Library core", 7.6, 7.6, 7.2, "L", 5, 1,
     "Incremental scan; 100k virtualized; SQL counts", "Multi-library, fingerprint dedupe, health dashboard"),
    (9, "B. Library & discovery", "Search", 7.4, 7.0, 7.4, "M", 5, 1,
     "FTS5 + top-k Levenshtein; one scored pass", "Semantic + voice search; natural-language filters"),
    (10, "B. Library & discovery", "Playlists", 6.9, 7.4, 6.8, "M", 4, 1,
     "Atomic apply + 20-step undo; one model", "Collaborative playlists, version history, AI generator"),
    (11, "B. Library & discovery", "Home & discovery", 6.7, 6.6, 7.0, "M", 3, 1,
     "Freezed HomeCubit; cache TTL fix; skeleton-first", "Mood/time mixes, cross-device resume, Pulsr Wrapped"),
    (12, "B. Library & discovery", "Detail screens", 6.9, 7.0, 7.0, "S", 3, 1,
     "Memoized streams; shared detail scaffold; virtualize", "Credits, versions, similar artists, album completeness"),
    (13, "B. Library & discovery", "Tag editor", 6.6, 7.2, 6.4, "M", 3, 1,
     "Controller-backed fields; 100-step undo; resumable batch", "Filename templates, fingerprint lookup, merge duplicates"),
    (14, "B. Library & discovery", "Duplicate finder & stats", 7.1, 6.9, 7.0, "M", 2, 3,
     "Chromaprint fingerprints; keep-best ranking; SQL stats", "Merge duplicates, storage treemap, library health score"),
    (15, "C. Online & accounts", "YouTube Music search", 7.0, 7.2, 7.0, "M", 4, 1,
     "Typed YTM errors; single-flight cache; hedged resolve", "Filters, artist radio, URL import, offline cache"),
    (16, "C. Online & accounts", "YouTube Music browse", 7.0, 6.5, 6.2, "M", 3, 0,
     "Cubit + generation guard; parallel fetch; fix clearCache", "Country charts, personalized rows, daily mixes"),
    (17, "C. Online & accounts", "Downloads", 7.4, 7.4, 7.0, "M", 4, 1,
     "Selection pruning; hash verify; quota guard", "Scheduled downloads, smart commute cache, priority queue"),
    (18, "C. Online & accounts", "Auth & account", 6.4, 6.6, 6.2, "M", 3, 1,
     "AppError mapping; single-flight refresh; multi-account FSM", "Passkeys, session management, family profiles"),
    (19, "C. Online & accounts", "Radio", 6.8, 7.2, 7.0, "M", 2, 1,
     "Radio Browser import; ICY metadata; buffer policy", "Favorites sync, recording, recommendations, station packs"),
    (20, "D. Social & sync", "Pulsr Party", 6.4, 5.8, 6.0, "L", 3, 1,
     "Client FSM; versioned queue; 100x10 load proof", "QR join, host migration, chat, per-member profiles"),
    (21, "D. Social & sync", "Cloud sync & backup", 6.3, 5.8, 6.0, "L", 3, 1,
     "Incremental sync + conflict UI; encrypted backups", "Multi-provider, queue handoff, E2E device sync"),
    (22, "D. Social & sync", "Scrobbling & stats", 7.2, 7.0, 7.0, "S", 2, 3,
     "Durable offline queue; two-way loved sync", "Stats v2, history import, recommendations"),
    (23, "D. Social & sync", "Discord Rich Presence", 7.0, 6.2, 7.0, "S", 1, 3,
     "Reconnect/backoff; privacy states; asset cache", "Buttons, progress, party invite, per-server privacy"),
    (24, "D. Social & sync", "Sharing & deep links", 6.9, 6.4, 7.0, "M", 2, 2,
     "Signed deep links + web fallback; card contrast", "QR, story cards, collaborative import, web embed"),
    (25, "E. Personalization & care", "Theme system & design", 8.5, 7.8, 8.6, "M", 4, 2,
     "Token-only theming; full golden matrix; motion budget", "Theme gallery, light parity, custom fonts/density"),
    (26, "E. Personalization & care", "Settings & profiles", 6.4, 7.6, 6.6, "M", 4, 1,
     "Settings search; split god-cubit; dirty-field fix", "Device presets, change history, expert mode, tuning packs"),
    (27, "E. Personalization & care", "Automation & device profiles", 6.7, 6.8, 6.8, "M", 3, 3,
     "Rule engine with priority/dry-run/audit log", "Visual builder, location triggers, car mode, NL rules"),
    (28, "E. Personalization & care", "Smart audio & hearing safety", 8.0, 7.8, 7.6, "M", 3, 2,
     "Match confidence + override; calibrated dose meter", "Audiogram import, lock-screen dose, personalized contour"),
    (29, "E. Personalization & care", "Quran mode", 7.0, 6.4, 7.0, "M", 3, 3,
     "Restore matrix; preamp headroom; ayah accuracy", "Word-by-word, memorization loop, prayer times, teacher mode"),
    (30, "E. Personalization & care", "Onboarding", 6.4, 6.0, 7.0, "S", 4, 1,
     "JIT permissions; first value <60 s; skip/resume", "Personalization quiz, library wizard, demo library"),
    (31, "F. Platform & experience", "Android integration", 7.4, 7.0, 7.6, "M", 3, 3,
     "Widget budget; complete media session; Auto browse tree", "Wear OS, QS tile, lock-screen lyrics, Material You"),
    (32, "F. Platform & experience", "Desktop & web parity", 4.8, 4.2, 5.2, "XL", 4, 3,
     "Declare tiers; WASAPI/CoreAudio/PipeWire exclusive output", "Desktop DSP parity, NAS library, desktop party host"),
    (33, "F. Platform & experience", "Accessibility & i18n", 6.5, 6.2, 6.4, "L", 5, 1,
     "100% labels, 48 dp, focus order, contrast AA", "10 languages, dyslexia font, haptic/audio parity"),
    (34, "F. Platform & experience", "App-wide performance", 7.4, 7.0, 6.8, "L", 5, 1,
     "Startup <900 ms; <250 MB; <0.5% jank; isolates", "Perf dashboard, baseline profiles, 120 Hz, low-RAM mode"),
    (35, "G. Foundation", "Security & privacy", 7.4, 6.8, 7.0, "L", 5, 1,
     "SQLCipher + app lock + log redaction + data controls", "Encrypted backups, privacy dashboard, reproducible builds"),
    (36, "G. Foundation", "Data layer & reliability", 7.5, 7.4, 7.4, "L", 5, 1,
     "EXPLAIN audit; FTS5; migration proof; integrity check", "Multi-library schema, sync revisions, one-tap rebuild"),
    (37, "G. Foundation", "CI / DX / test", 8.8, 8.2, 8.0, "M", 4, 0,
     "Green analyze gate; delete probes; regenerate coverage", "Theme goldens, perf gates, 24 h soak, signed releases"),
]

CAPS = {32: 9.0, 33: 9.8}
EFFORT_SCORE = {"S": 1, "M": 2, "L": 3, "XL": 4}

HEADER_FILL = PatternFill("solid", fgColor="14172B")
HEADER_FONT = Font(name="Segoe UI", bold=True, color="F2F3FF", size=10)
BODY_FONT = Font(name="Segoe UI", size=10, color="1B1D2A")
MUTED_FONT = Font(name="Segoe UI", size=9, color="5A5F73")
TITLE_FONT = Font(name="Segoe UI Semibold", bold=True, size=18, color="14172B")
SUBTITLE_FONT = Font(name="Segoe UI", size=10, color="5A5F73")
ACCENT_FILL = PatternFill("solid", fgColor="9B9EF5")
BAND_FILL = PatternFill("solid", fgColor="F6F6FC")
THIN = Side(style="thin", color="E2E2EE")
BORDER = Border(bottom=THIN)


def style_header(ws, row: int, cols: int) -> None:
    for c in range(1, cols + 1):
        cell = ws.cell(row=row, column=c)
        cell.fill = HEADER_FILL
        cell.font = HEADER_FONT
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    ws.row_dimensions[row].height = 32


def add_table(ws, ref: str, name: str) -> None:
    table = Table(displayName=name, ref=ref)
    table.tableStyleInfo = TableStyleInfo(
        name="TableStyleLight1", showRowStripes=True, showColumnStripes=False
    )
    ws.add_table(table)


wb = Workbook()

# ---------------------------------------------------------------- Read me
ws = wb.active
ws.title = "Read me"
ws.sheet_view.showGridLines = False
ws["B2"] = "PULSR — MAXIMUM-RATE SCORECARD"
ws["B2"].font = TITLE_FONT
ws["B3"] = "Every feature scored today, the 10/10 ceiling, and the distance between them."
ws["B3"].font = Font(name="Segoe UI", size=11, color="6C70DC", italic=True)
ws["B5"] = "Date"
ws["B5"].font = Font(bold=True)
ws["C5"] = "2026-10-26"
ws["B6"] = "Scope"
ws["B6"].font = Font(bold=True)
ws["C6"] = "37 features / 7 domains"
ws["B7"] = "Composite"
ws["B7"].font = Font(bold=True)
ws["C7"] = "0.5 x Quality + 0.3 x Function + 0.2 x Experience"
ws["B8"] = "Snapshot"
ws["B8"].font = Font(bold=True)
ws["C8"] = (
    "Working tree is dirty. flutter analyze = 2 warnings (untracked _repro test); "
    "lcov coverage = 73.4% vs 77.0% floor."
)
ws["C8"].alignment = Alignment(wrap_text=True, vertical="top")
ws.merge_cells("C8:F8")
ws.row_dimensions[8].height = 42
ws["B9"] = "Headline"
ws["B9"].font = Font(bold=True)
ws["C9"] = (
    "7.17 / 10 composite (Q 7.25, F 7.09, X 7.09). Strongest domain: A. Playback & DSP 8.14. "    "Weakest: F. Platform & experience 6.39. Updated 2026-10-27: YTM Browse cubit, live radio directory, green suite (5,589) / coverage (77.66%)."
)
ws["C9"].font = Font(name="Segoe UI", size=10, bold=True, color="6C70DC")
ws.merge_cells("C9:G9")

notes = [
    ("What this is", "A decision-grade ceiling map: where each feature stands, what 10/10 engineering would change, and which functions would complete it."),
    ("What this is not", "Not a fresh line-by-line re-audit of 211k LOC. Current scores synthesize gaps.md (2026-10-02), the 2026-10-04 remediation, and fresh 2026-10-26 checks."),
    ("How to use it", "Sort by Leverage to find the best return per week of work. Filter by Wave to plan. Read the dossier for the per-feature definition of 10/10."),
    ("Score bands", "9-10 excellent | 7-8 strong | 5-6 functional with real gaps | 3-4 weak/high-risk | 0-2 broken."),
    ("Hard caps", "Desktop/web parity is capped at 9.0 by browser sandbox limits; accessibility is capped at 9.8 by platform semantics. Everything else targets 10.0."),
]
r = 10
for label, text in notes:
    ws.cell(row=r, column=2, value=label).font = Font(name="Segoe UI", bold=True, size=10)
    ws.cell(row=r, column=3, value=text).font = BODY_FONT
    ws.cell(row=r, column=3).alignment = Alignment(wrap_text=True, vertical="top")
    ws.merge_cells(start_row=r, start_column=3, end_row=r, end_column=7)
    ws.row_dimensions[r].height = 34
    r += 1

ws.column_dimensions["A"].width = 2
ws.column_dimensions["B"].width = 20
for col in "CDEFG":
    ws.column_dimensions[col].width = 22

# ---------------------------------------------------------------- Scorecard
ws = wb.create_sheet("Scorecard")
ws.sheet_view.showGridLines = False
headers = [
    "#", "Domain", "Feature", "Q", "F", "X", "Composite", "Gap", "Cap",
    "Effort", "Impact", "Leverage", "Wave", "Top optimisation", "Top function",
]
ws.append(headers)
style_header(ws, 1, len(headers))

for row in ROWS:
    idx, domain, feature, q, f, x, effort, impact, wave, opt, func = row
    composite = round(0.5 * q + 0.3 * f + 0.2 * x, 2)
    cap = CAPS.get(idx, 10.0)
    gap = round(cap - composite, 2)
    leverage = round((impact * gap) / EFFORT_SCORE[effort], 2)
    ws.append([idx, domain, feature, q, f, x, composite, gap, cap, effort, impact, leverage, wave, opt, func])

last = ws.max_row
for r in range(2, last + 1):
    for c in range(1, len(headers) + 1):
        cell = ws.cell(row=r, column=c)
        cell.font = BODY_FONT
        cell.border = BORDER
        if r % 2 == 0:
            cell.fill = BAND_FILL
        if c in (1, 4, 5, 6, 7, 8, 9, 11, 12, 13):
            cell.alignment = Alignment(horizontal="center", vertical="center")
        elif c in (2,):
            cell.alignment = Alignment(vertical="center")
        else:
            cell.alignment = Alignment(vertical="center", wrap_text=(c in (3, 14, 15)))
    ws.row_dimensions[r].height = 34

for col in ("D", "E", "F", "G", "H"):
    ws.conditional_formatting.add(
        f"{col}2:{col}{last}",
        ColorScaleRule(
            start_type="num", start_value=4, start_color="FF5252",
            mid_type="num", mid_value=7, mid_color="FFB300",
            end_type="num", end_value=10, end_color="4CAF50",
        ),
    )
ws.conditional_formatting.add(
    f"L2:L{last}",
    ColorScaleRule(
        start_type="min", start_color="FFFFFF",
        end_type="max", end_color="9B9EF5",
    ),
)

widths = {
    "A": 5, "B": 24, "C": 30, "D": 6, "E": 6, "F": 6, "G": 11, "H": 7,
    "I": 7, "J": 8, "K": 8, "L": 10, "M": 7, "N": 52, "O": 58,
}
for col, width in widths.items():
    ws.column_dimensions[col].width = width
ws.freeze_panes = "D2"
ws.auto_filter.ref = f"A1:O{last}"
add_table(ws, f"A1:O{last}", "ScorecardTable")

# ---------------------------------------------------------------- Domains
ws = wb.create_sheet("Domains")
ws.sheet_view.showGridLines = False
ws.append(["Domain", "Features", "Q", "F", "X", "Composite", "Verdict"])
style_header(ws, 1, 7)
verdicts = {
    "A. Playback & DSP": "The moat. Closest to maximum.",
    "B. Library & discovery": "Good bones; scale and polish missing.",
    "C. Online & accounts": "YTM browse is the weakest feature in the app.",
    "D. Social & sync": "Infrastructure ahead of product.",
    "E. Personalization & care": "Strong identity; settings and onboarding lag.",
    "F. Platform & experience": "Android good, everywhere else thin.",
    "G. Foundation": "Strong CI, weak privacy floor.",
}
domains: OrderedDict[str, list[tuple[float, float, float, float]]] = OrderedDict()
for row in ROWS:
    _, domain, _f, q, f, x, *rest = row
    composite = 0.5 * q + 0.3 * f + 0.2 * x
    domains.setdefault(domain, []).append((q, f, x, composite))

for domain, vals in domains.items():
    n = len(vals)
    ws.append([
        domain, n,
        round(sum(v[0] for v in vals) / n, 2),
        round(sum(v[1] for v in vals) / n, 2),
        round(sum(v[2] for v in vals) / n, 2),
        round(sum(v[3] for v in vals) / n, 2),
        verdicts[domain],
    ])
last = ws.max_row
ws.append([
    "Whole app", len(ROWS),
    round(sum(r[3] for r in ROWS) / len(ROWS), 2),
    round(sum(r[4] for r in ROWS) / len(ROWS), 2),
    round(sum(r[5] for r in ROWS) / len(ROWS), 2),
    round(sum(0.5 * r[3] + 0.3 * r[4] + 0.2 * r[5] for r in ROWS) / len(ROWS), 2),
    "Excellent player, incomplete product.",
])
for r in range(2, ws.max_row + 1):
    for c in range(1, 8):
        cell = ws.cell(row=r, column=c)
        cell.font = BODY_FONT
        cell.border = BORDER
        if c in (2, 3, 4, 5, 6):
            cell.alignment = Alignment(horizontal="center")
        if r == ws.max_row:
            cell.font = Font(name="Segoe UI", bold=True, size=10, color="14172B")
            cell.fill = PatternFill("solid", fgColor="E8E8FB")

for col, width in {"A": 26, "B": 9, "C": 7, "D": 7, "E": 7, "F": 11, "G": 52}.items():
    ws.column_dimensions[col].width = width

chart = BarChart()
chart.type = "bar"
chart.style = 10
chart.title = "Composite by domain (max 10)"
chart.y_axis.title = "Score"
chart.x_axis.title = None
data = Reference(ws, min_col=6, min_row=1, max_row=last)
cats = Reference(ws, min_col=1, min_row=2, max_row=last)
chart.add_data(data, titles_from_data=True)
chart.set_categories(cats)
chart.legend = None
chart.height = 7.5
chart.width = 16
chart.y_axis.scaling.min = 0
chart.y_axis.scaling.max = 10
ws.add_chart(chart, "I2")

# ---------------------------------------------------------------- Quick wins
ws = wb.create_sheet("Quick wins")
ws.sheet_view.showGridLines = False
ws.append(["Rank", "Feature", "Domain", "Leverage", "Gap", "Effort", "Impact", "Top optimisation"])
style_header(ws, 1, 8)

quick = []
for row in ROWS:
    idx, domain, feature, q, f, x, effort, impact, wave, opt, func = row
    composite = round(0.5 * q + 0.3 * f + 0.2 * x, 2)
    gap = round(CAPS.get(idx, 10.0) - composite, 2)
    leverage = round((impact * gap) / EFFORT_SCORE[effort], 2)
    quick.append((leverage, feature, domain, gap, effort, impact, opt))
quick.sort(reverse=True)
for rank, (leverage, feature, domain, gap, effort, impact, opt) in enumerate(quick[:12], start=1):
    ws.append([rank, feature, domain, leverage, gap, effort, impact, opt])
for r in range(2, ws.max_row + 1):
    for c in range(1, 9):
        cell = ws.cell(row=r, column=c)
        cell.font = BODY_FONT
        cell.border = BORDER
        cell.alignment = Alignment(
            horizontal="center" if c in (1, 4, 5, 6, 7) else "left",
            vertical="center",
            wrap_text=(c == 8),
        )
    ws.row_dimensions[r].height = 30
for col, width in {"A": 7, "B": 30, "C": 24, "D": 10, "E": 7, "F": 8, "G": 8, "H": 80}.items():
    ws.column_dimensions[col].width = width
ws.freeze_panes = "A2"
ws["J2"] = "Leverage = impact x gap / effort. This is a quick-win ranking, not the strategic order; see Roadmap."
ws["J2"].font = MUTED_FONT
ws.merge_cells("J2:N2")

# ---------------------------------------------------------------- Roadmap
ws = wb.create_sheet("Roadmap")
ws.sheet_view.showGridLines = False
ws.append(["Wave", "Theme", "Representative items", "Exit criteria", "Effort"])
style_header(ws, 1, 5)
roadmap = [
    ("0", "Stop the leaks", "Delete/move probe & repro tests; regenerate coverage; fix download selection; empty-catch burn-down to <250; settings search slice", "analyze = 0; no temp tests; coverage above floor; no wrong-item deletion", "0-2 weeks"),
    ("1", "Scale & trust", "100k benchmark + FTS5; queue actor; SQLCipher + app lock; YTM Browse cubit; Party FSM + QR; cloud conflict UI; a11y sweep", "100k p95 <30 ms; search <50 ms; 0 lost updates; encrypted DB; party reconnect <1 s", "2-8 weeks"),
    ("2", "Audio moat", "Multichannel DSP; DSD512/768k; UAC2 volume + rate follow; room wizard; word-level lyrics; theme gallery", "Verified on 3 DACs; wizard <5 min; 9 themes golden-tested", "6-16 weeks"),
    ("3", "Everywhere", "Desktop exclusive output + DSP; iOS CoreAudio port; Android Auto/Wear; semantic search; 10 languages", "Tier 2 desktop shipped; iOS beta; Auto/Wear live; 10 locales", "3-9 months"),
]
for row in roadmap:
    ws.append(row)
for r in range(2, ws.max_row + 1):
    for c in range(1, 6):
        cell = ws.cell(row=r, column=c)
        cell.font = BODY_FONT
        cell.border = BORDER
        cell.alignment = Alignment(wrap_text=True, vertical="top")
    ws.row_dimensions[r].height = 72
for col, width in {"A": 7, "B": 18, "C": 70, "D": 55, "E": 12}.items():
    ws.column_dimensions[col].width = width
ws.freeze_panes = "A2"

# ---------------------------------------------------------------- Rubric
ws = wb.create_sheet("Rubric")
ws.sheet_view.showGridLines = False
ws.append(["Dimension", "A 10/10 feature has...", "Weight"])
style_header(ws, 1, 3)
rubric = [
    ("Architecture", "Clear layering, small cohesive units, dependency inversion, no god files/objects", "Q"),
    ("Bug density", "No known functional defects; edge cases covered by tests", "Q"),
    ("State", "One source of truth, immutable state, no duplication outside the store", "Q"),
    ("Errors", "Typed AppError, no silent/swallowed failures, user-visible recovery", "Q"),
    ("Performance", "No UI-isolate heavy work, bounded per-frame work, no O(n^2)/N+1", "Q"),
    ("Memory", "Bounded caches, deterministic disposal, no leaks", "Q"),
    ("Concurrency", "Mutex/generation guards on shared mutable state; no lost updates", "Q"),
    ("Hygiene", "No dead code, no avoidable dynamic, no oversized files, full l10n", "Q"),
    ("Security", "Input/path/URL validation, no credential leakage, no SSRF/arbitrary file ops", "Q"),
    ("Accessibility", "Semantics on every control, >=48 dp targets, dynamic type/RTL safe", "Q"),
    ("CI / DX / ADR", "Enforced by CI, dedicated tests, documented decisions, real coverage floor", "Q"),
    ("Function coverage", "Every item in the category's credible maximum feature set is present and coherent", "F"),
    ("Experience", "Instant, legible, accessible, polished in daily use; no dead ends", "X"),
]
for row in rubric:
    ws.append(row)
for r in range(2, ws.max_row + 1):
    for c in range(1, 4):
        cell = ws.cell(row=r, column=c)
        cell.font = BODY_FONT
        cell.border = BORDER
        cell.alignment = Alignment(wrap_text=True, vertical="top")
for col, width in {"A": 20, "B": 95, "C": 8}.items():
    ws.column_dimensions[col].width = width
ws.freeze_panes = "A2"

OUT.parent.mkdir(parents=True, exist_ok=True)
wb.save(OUT)
print(f"Wrote {OUT} ({OUT.stat().st_size / 1024:.1f} KB)")
