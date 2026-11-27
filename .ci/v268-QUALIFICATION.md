AP-BIM Tools 2.6.8 — qualification only

- Mode C reads outer title frame in source Paper Space before projection. Grid uses frame top-left, max width per column and max height per row, exact user gap. A missing rectangle falls back to paper-only bounds (logged); no model projection extents are used.
- Validates grid math for 13 mixed-size frames, 1/5/6/10/20 columns, and checks saved block positions and scale after reopen.
- A/B normalize page setup to detected outer rectangular frame only when a compatible 1:1 plot device/media is available; preserve original setup and log when not qualified. Floating viewport camera and scale remain untouched. No desktop fallback added.
- Hosted build does not run Revit/AutoCAD. Actual DWG layout background, plot preview, mixed title block families, and 6+ columns require workstation validation.
