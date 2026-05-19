# ⚡ MightyBoost

> Windows 10/11 optimizer with one-liner launch, full undo, and 190+ tweaks.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)](#)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows&logoColor=white)](#)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](docs/CONTRIBUTING.md)

**🇷🇺 [Русская версия](README.ru.md)** &nbsp;|&nbsp; **🇬🇧 English**

---

## 🚀 Run it

Open PowerShell **as administrator** and paste:

```powershell
irm "https://raw.githubusercontent.com/mighty-boost/mighty-boost/main/boost.ps1" | iex
```

That's it — no install, no .exe, just open-source PowerShell + JSON. The GUI opens in a few seconds.

> **No admin yet?** The script will re-launch itself with an UAC prompt.

---

## 🎯 Why MightyBoost?

| | MightyBoost | Typical "optimizer" |
|---|---|---|
| **Open source** | ✅ MIT, 100% PS + JSON | ❌ Closed `.exe` |
| **Undo every change** | ✅ Per-tweak `.reg` backup + System Restore Point | ❌ Hope and prayers |
| **One-liner launch** | ✅ `irm \| iex`, zero install | ❌ Installer + bundled adware |
| **Bilingual UI** | ✅ Russian + English, auto-detect | ⚠️ English-only |
| **Easy to extend** | ✅ Add a tweak with one JSON block | ❌ Full rebuild needed |
| **No bundled binaries** | ✅ Only scripts you can read | ❌ Mystery binaries |

---

## 🧰 What's inside (MVP: 196 features)

| Module | Count | Examples |
|---|---|---|
| 🔒 **Privacy & telemetry** | 24 tweaks | DiagTrack, CEIP, Advertising ID, Activity History, Cortana, Bing search, lock-screen ads, Copilot, Windows Recall, Edge telemetry, OneDrive auto-start |
| ⚡ **Performance** | 13 tweaks | Visual effects, transparency, SysMain, Search indexer, NDU, NTFS lastaccess, Fast Startup, GPU TDR, menu delay |
| 🎮 **Gaming** | 7 tweaks | GameDVR, FullscreenOptimizations, HAGS, mouse accel, MMCSS priorities, Nagle's algorithm |
| 🌐 **Network** | 6 tweaks | NetBIOS, LLMNR, network throttling, TCP autotuning, IPv6, Cloudflare DNS |
| 🪟 **UI / Explorer** | 10 tweaks | Show extensions, hidden files, classic context menu (Win11), left-aligned taskbar, hide widgets/chat/news |
| 🗑️ **Debloat (Appx)** | 30 packages | Cortana, Xbox suite, OneDrive, Copilot, Teams (consumer), Skype, Mail, Maps, Solitaire, Bing Weather/News, Clipchamp |
| ⚙️ **Services** | 30 services | DiagTrack, WSearch, SysMain, Fax, Xbox services, WerSvc, Remote Registry, BITS |
| 📅 **Scheduled tasks** | 5 tasks | Office telemetry, Feedback Hub, WaaSMedic |
| 📦 **App installer (winget)** | 71 programs | Chrome, Firefox, Brave, VLC, 7-Zip, Telegram, Discord, Steam, OBS, VS Code, Git, Node, Python, Spotify, ShareX |
| 🧹 **Cleanup** | 8 targets | Temp, Prefetch, Delivery Optimization cache, CBS logs, event logs, thumbnails, recycle bin |

> Architecture is **data-driven**: every tweak is one JSON object — adding new features doesn't touch the core engine.

---

## 🛡️ Safety first

Every change is reversible:

1. A **System Restore Point** is created before applying a tweak group.
2. Every touched registry key is exported to `.reg` in `%AppData%\MightyBoost\Backups\<timestamp>\` before being modified.
3. Each applied tweak is recorded in `%AppData%\MightyBoost\applied.json` with its undo recipe — the **Restore** tab in the GUI can roll it back with one click.
4. Dangerous actions (removing Edge, disabling Defender, IPv6 etc.) show a confirmation with a warning.
5. **No signed binaries shipped** — you can read every line that runs on your machine.

---

## 🖼️ Screenshots

> _Add screenshots in `docs/screenshots/` (Home, Privacy, Debloat, Restore tabs)._

---

## 🌍 Localization

| Code | Language | Status |
|---|---|---|
| `en` | English | ✅ |
| `ru` | Русский | ✅ |

UI auto-selects based on `Get-Culture`. Want another language? See [CONTRIBUTING.md](docs/CONTRIBUTING.md#-locales).

---

## 🧑‍💻 Contributing

We want **easy** contributions. Most of the project is data, not code.

To add a new tweak you don't need to know PowerShell — just add a JSON object to `src/data/tweaks.json`:

```json
{
  "id": "priv-something-new",
  "category": "Privacy",
  "presets": ["balanced","aggressive"],
  "win": ["10","11"],
  "name":        { "ru": "...", "en": "..." },
  "description": { "ru": "...", "en": "..." },
  "apply": [
    { "type": "registry", "path": "HKLM:\\...", "name": "Foo", "kind": "DWord", "value": 0 }
  ],
  "undo": [
    { "type": "registry", "path": "HKLM:\\...", "name": "Foo", "delete": true }
  ]
}
```

Send a PR. CI runs PSScriptAnalyzer and validates JSON. See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for the full guide.

---

## ⚙️ Local development

```powershell
git clone https://github.com/mighty-boost/mighty-boost.git
cd mighty-boost
.\boost.ps1 -Local       # uses local files instead of fetching from GitHub
```

Useful flags:

| Flag | Effect |
|---|---|
| `-Local` | Force local mode (don't fetch modules from GitHub). |
| `-Branch <name>` | Pull modules from a different branch (default: `main`). |
| `-NoElevate` | Don't auto-elevate to admin (most tweaks will fail). |

---

## 📜 License

MIT — see [LICENSE](LICENSE).

---

## 🙏 Credits / Prior art

MightyBoost stands on the shoulders of these excellent projects (architectural reference + tweak research):

- [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil)
- [hellzerg/optimizer](https://github.com/hellzerg/optimizer)
- [builtbybel/privatezilla](https://github.com/builtbybel/privatezilla)
- [HotCakeX/Harden-Windows-Security](https://github.com/HotCakeX/Harden-Windows-Security)
- [Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat)

---

⭐ If this project helped you, star the repo — it really helps others find it.
