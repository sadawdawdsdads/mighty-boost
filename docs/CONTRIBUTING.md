# Contributing to MightyBoost

Thanks for considering a contribution! The project is intentionally **data-driven** so you can extend it without writing PowerShell — most contributions are JSON edits.

## TL;DR

- Adding a tweak: edit `src/data/tweaks.json`
- Adding an app to the installer: edit `src/data/apps.json`
- Adding an Appx package to debloat: edit `src/data/debloat.json`
- Adding a service preset: edit `src/data/services.json`
- Adding a scheduled task to disable: edit `src/data/tasks.json`
- Translations: edit `src/data/locales/<code>.json`

For real code (modules, UI, engine) see `src/core/` and `src/ui/`.

## 🧪 Local testing

```powershell
.\boost.ps1 -Local
```

Run from the repo root. `-Local` makes the script read modules and data from the working tree instead of GitHub.

## 📝 Tweak format

A tweak is one JSON object inside `src/data/tweaks.json`. Required fields:

| Field | Type | Description |
|---|---|---|
| `id` | string | Unique slug like `priv-disable-foo`. Used in logs, applied.json, and the Restore tab. |
| `category` | string | One of `Privacy`, `Performance`, `Gaming`, `Network`, `UI`. |
| `presets` | string[] | Subset of `["safe","balanced","aggressive"]`. |
| `win` | string[] | `["10"]`, `["11"]`, or both. |
| `name` | `{ru,en}` | Localized title shown in the UI. |
| `description` | `{ru,en}` | Localized description shown as a tooltip. |
| `apply` | action[] | Actions to run when the tweak is applied. |
| `undo` | action[] | Actions that revert the apply. Required — every tweak must be reversible. |

Optional:

| Field | Type | Description |
|---|---|---|
| `warning` | `{ru,en}` | Localized warning shown for dangerous tweaks. |
| `source` | url | Link to a known reference (Microsoft Learn, GitHub thread). |

### Action types

#### `registry`
```json
{ "type": "registry", "path": "HKLM:\\Software\\...", "name": "Foo", "kind": "DWord", "value": 0 }
```
- `kind`: `DWord`, `QWord`, `String`, `ExpandString`, `MultiString`, `Binary`. Default: `DWord`.
- For binary: `value` is a hex string like `"9012038010000000"`.
- To delete a value: `{ "type": "registry", "path": "...", "name": "Foo", "delete": true }`.

#### `service`
```json
{ "type": "service", "name": "DiagTrack", "startup": "Disabled", "stop": true }
```
- `startup`: `Automatic`, `AutomaticDelayed`, `Manual`, `Disabled`.
- `stop`: also stop the service if running.
- `start`: also start the service if stopped.

#### `task`
```json
{ "type": "task", "path": "\\Microsoft\\Windows\\Foo\\", "name": "Bar", "state": "Disabled" }
```
- `state`: `Disabled` or `Ready`.

#### `appx`
```json
{ "type": "appx", "remove": "*Microsoft.SkypeApp*" }
```
- Wildcards supported. Removed for all users + provisioned package.

## ✅ Checklist before opening a PR

- [ ] `apply` and `undo` are symmetric — applying then undoing returns the system to its original state.
- [ ] If your tweak only applies to a specific OS version, set `win` correctly.
- [ ] Both `ru` and `en` fields are filled in. If you don't know Russian, ask in the PR — a reviewer will add it.
- [ ] Don't introduce `.exe` or other binaries.
- [ ] Run PSScriptAnalyzer locally if you touched `.ps1` files.

## 🌐 Locales

Locale files live in `src/data/locales/`. To add a language:

1. Copy `en.json` to `<code>.json` (use [ISO 639-1](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes)).
2. Translate every value.
3. Update the locale-detection logic in `src/core/I18n.ps1` (or open an issue for it).

## 🐞 Reporting bugs

Open an issue with:

- Windows edition + build (`winver`)
- Tweak ID(s) involved
- The relevant section from `%AppData%\MightyBoost\Logs\session-*.log`
- Screenshot if the UI is involved

## 📐 Coding style

- PowerShell: 4 spaces, single quotes by default, no aliases (`Get-ChildItem`, not `gci`).
- Functions are `Verb-MBNoun` so the prefix avoids collisions with built-ins.
- All errors must be logged via `Write-MBLog -Level ERROR/WARN`.
- Side-effecting helpers should write to `applied.json` so they can be undone.
