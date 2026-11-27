# 2.6.1 geometry qualification (not production)
- AppBundle runtime loading was confirmed by user logs with SECURELOAD=1.
- Mode B: disjoint model blocks, shifted floating viewport camera and raster mapping.
- Mode C: paper-only and rectangular top orthographic viewports with zero twist and no frozen layers. Other cases are rejected. Clipped nested blocks preserve editability, not general EXPORTLAYOUT equivalence.
- Added synthetic raster and overlapping-model regression checks to in-host preflight. Requires actual AutoCAD to execute. CI checks compilation and packaging only.
- User's DWG files and images remain private, not committed.
- Release gate still requires actual plots, viewport and image fidelity, no acad.exe, correct file names/rollback and all three modes on real drawings.