# Svr2Desktop

Desktop-like tuning for Windows Server 2016 / 2019 / 2022 / 2025.

Pure PowerShell, no third-party dependencies. It removes login/shutdown waits and popups, enables the desktop experience, tunes power and network for server scenarios, trims unused services, and adds operational tooling. **Every change is read back and verified; everything except files deleted by the cleanup stage is reversible.**

> Upstream baseline: community edition `Windows Server 2016-2025 to desktop.bat` v8.1. This repository is a rewritten and audited version. Since v11.0, "security downgrade" has been refactored into an explicit, opt-in stage.

---

## ⚠️ Security notice — read before use

This script offers `Downgrade` / `VBS` stages that relax system defenses:

| ID | Effect |
|---|---|
| SEC10 | Silent UAC elevation for admins (`ConsentPromptBehaviorAdmin=0`; **`EnableLUA=1` is kept — UAC is not disabled**) |
| SEC11 | Turns off Defender real-time protection and service (**reversible; components are not uninstalled**) |
| SEC12 | Password never expires (**length and complexity requirements are untouched**) |
| SEC13 | Suppresses Security Center alerts and tray icon |
| VBS | Virtualization-based security downgrade |

**Design constraints (do not bypass):**

1. These are **never run by default**. You must explicitly choose menu `[10]`/`[9]`, `-Stage Downgrade`, `-Stage VBS`, or `-Stage All`; `-SkipDowngrade` / `-SkipVBS` exclude them even under `-Stage All`.
2. Before execution the script prints a risk summary and the rollback command and asks for confirmation.
3. **The config whitelist contains no keys for these items** — a JSON file placed next to the script cannot silently enable them.
4. Still **not provided**: fully disabling the UAC framework, uninstalling Defender, disabling SEHOP/DEP, or zeroing password complexity/minimum length.

**Warning**: combined, the items above form a complete attack chain — *weak password → silent UAC elevation → no AV → no alerts*. They are designed for **isolated, trusted lab or home environments** and **must not be used on network-exposed production servers**. Assess compliance and security responsibility yourself; the authors accept no liability for misuse.

One coupling to remember: SEC10 sets both `ConsentPromptBehaviorAdmin=0` and `PromptOnSecureDesktop=0` (the latter alone is a classic UAC-bypass foothold). If you later restore `ConsentPromptBehaviorAdmin` to `2` or `5`, **restore `PromptOnSecureDesktop` to `1` at the same time**.

---

## Four rules

| Rule | Meaning |
|---|---|
| **Read back everything** | Compare the new value with the expected one; never treat "command succeeded" as done |
| **Back every verdict with evidence** | If a check fails, show the measured value — or state plainly that it was not captured |
| **Make everything reversible** | Pre-change values are registered in five backup channels plus a native-command replay channel |
| **Never default to downgrade** | Nothing that trades security for convenience is on the default path |

---

## Usage

Start PowerShell as Administrator in the script directory:

```powershell
.\Svr2Desktop.ps1                  # interactive menu
.\Svr2Desktop.ps1 -Verify          # read-only baseline; changes nothing
.\Svr2Desktop.ps1 -WhatIf          # full dry run; no writes
.\Svr2Desktop.ps1 -Stage All -Json -Force -ExitOnFail   # unattended full run
.\Svr2Desktop.ps1 -Stage Desktop,Ops -Force            # selected stages
.\Svr2Desktop.ps1 -Stage Downgrade                     # ⚠️ security downgrade only
```

Or double-click `Svr2Desktop.cmd`: it prefers `pwsh.exe`, falls back to Windows PowerShell 5.1, requests elevation exactly once, pauses only for double-clicks, and never pauses for unattended runs.

**Recommended flow**: `-Verify` (baseline) → `-WhatIf` → run → reboot → `-Verify` again. **The diff of the two `-Verify` reports is proof of what actually changed.**

Common switches:

| Switch | Purpose |
|---|---|
| `-Full` | Expand all evidence lines (default summary folds passing ones) |
| `-NoEvidence` | Silence on-screen evidence; logs remain complete |
| `-Json` | Also emit machine-readable `Svr2Desktop_result.json` |
| `-SkipDowngrade` / `-SkipVBS` | Exclude downgrades even under `-Stage All` |
| `-DisableSpooler` / `-DisableWLAN` | Enable two opt-in items |
| `-NoRestartPrompt` | Skip the reboot prompt |
| `-ExitOnFail` | Exit-code contract: `0` clean / `2` FAIL / `1` fatal |
| `-ConfigPath` / `-BackupRoot` | Override config file / backup root |

> **Two-step reboot confirmation (v13.1+)**: after `Reboot now …? [Y/N]`, you must also type `OK` (`yes` is rejected, empty input cancels). Add `-Force` or `-NoRestartPrompt` to skip.

Stages: Desktop 15 / Performance 8 / Network 3 / Services 4+2 opt-in / Security 5 / Ops 3 / Cleanup 2 (destructive, **irreversible**) / Downgrade 4 and VBS 1 (**opt-in only**).

---

## Files

| File | Purpose |
|---|---|
| `Svr2Desktop.ps1` | Main script (v13.3, UTF-8 **with BOM** — preserve this encoding) |
| `Svr2Desktop.cmd` | Double-click launcher with host selection and single elevation request |
| `Svr2Desktop.config.json` | Optional config sample; delete it to use built-in defaults. Whitelist design documented inline |
| `CHANGELOG.md` | v11.0 → v13.3 changes and real-machine acceptance records |
| `Svr2Desktop_V12_调优项说明.md` | Chinese per-item guide (**see version note**) |
| `Svr2Desktop_Audit_2026-09-22.md` | v11.15 static audit with time-boxed action items |
| `Svr2Desktop_v9.0_bat_legacy.bat` | Archived upstream v9.0 batch file, reference only, **do not run** |

**Version note**: `Svr2Desktop_V12_调优项说明.md` was written for the **V12** snapshot. It includes some later V13.1/V13.3 notes, but a few sentences (e.g. "the script is still 12.0") were not updated. **The authoritative version is the `Version` header and `$script:VER` in `Svr2Desktop.ps1`; latest changes are in `CHANGELOG.md`.** The guide is reproduced unmodified to stay byte-identical with the internal source.

---

## License

[MIT](LICENSE) © 2026 Bob Yin

The upstream baseline `Windows Server 2016-2025 to desktop.bat` v8.1 is a community release; the original upstream file is not redistributed here — only the rewritten and audited content.
