# Next prompt: RADE

Updated: 2026-11-28 Central (Kit 16.0.0 synced, engine-v51). State, open items, older plans: [handoff detail](reviews/2026-11-18-handoff-detail.md).

- Engine v50: app-agnostic build (`engine/rade_build.py`), consolidated PowerShell/UI modules (`07-checks.ps1`, `14-sp-restore.ps1`, `ui-{theme,shell,cards,runner}.ps1`), `DEC-NIPR` hardened (`nipr-safe: on`), Fulcrum Dark v2.1.1, Restore single-session + retry/backoff + path guard, Diagnose timestamp fix.
- Engine v51 (PR 217): `engine/rade_ui.ps1` is again the one app-facing UI file (moved from `engine/ps/window/ui-theme.ps1`; DEC-NIPR 2). Open: docs/engine.md and docs/window-design.md still name `rade_ui_text.ps1` and `rade_parts.py`, which no longer exist; recount the engine files.
- Open: work-computer proof (TLS 1.3 on older Windows, ISE paste proof, shortcut repair).
