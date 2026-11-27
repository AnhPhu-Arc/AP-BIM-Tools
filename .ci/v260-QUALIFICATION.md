# 2.6.0 headless qualification (not a production release)

- User sample drawings stay outside this public repository.
- Installed 2.5.1 headless assemblies match installer bytes and Autodesk API assembly identities.
- Test explicit /al bundle in Program Files without lowering SECURELOAD. Capture host variables and INIT marker.
- All new qualification export paths must not launch acad.exe.
- Mode C only supports paper-only sheets at this stage. Any floating viewport is rejected before publish, not silently discarded. Full projection, clipping, layer overrides, annotation fidelity and model-scale behavior remain development work.
- GitHub build checks packaging only. Runtime acceptance requires licensed AutoCAD on a separate authorized Windows runner, using private test inputs; no claim of runtime success from build alone.
- Required release gate: A/B/C on 6 supplied sheets plus multi-viewport and mixed scale, 50+ sheets, image/link integrity, collision rollback, no acad.exe launch, output count and visual comparison.
