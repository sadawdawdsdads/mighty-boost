# ⚡ MightyBoost

> Оптимизатор Windows 10/11 с запуском одной командой, полным откатом и 190+ твиками.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)](#)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows&logoColor=white)](#)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](docs/CONTRIBUTING.md)

**🇷🇺 Русский** &nbsp;|&nbsp; **🇬🇧 [English](README.md)**

---

## 🚀 Запуск

Открой PowerShell **от имени администратора** и вставь:

```powershell
irm "https://raw.githubusercontent.com/mighty-boost/mighty-boost/main/boost.ps1" | iex
```

И всё — никакой установки, никакого .exe, только открытый PowerShell + JSON. GUI откроется через пару секунд.

> **Нет прав админа?** Скрипт сам перезапустится через UAC.

---

## 🎯 Почему MightyBoost?

| | MightyBoost | Обычный «оптимизатор» |
|---|---|---|
| **Открытый исходник** | ✅ MIT, 100% PS + JSON | ❌ Закрытый `.exe` |
| **Откат каждого изменения** | ✅ `.reg` бэкап + точка восстановления | ❌ «А если что — переустановишь» |
| **Запуск одной командой** | ✅ `irm \| iex`, без установки | ❌ Инсталлер + adware в комплекте |
| **Двуязычный UI** | ✅ Русский + English, авто-выбор | ⚠️ Часто только English |
| **Легко расширять** | ✅ Один JSON-блок = новый твик | ❌ Нужна полная пересборка |
| **Без неизвестных бинарей** | ✅ Только скрипты, которые ты видишь | ❌ Магические .exe |

---

## 🧰 Что внутри (MVP: 196 функций)

| Модуль | Кол-во | Примеры |
|---|---|---|
| 🔒 **Приватность и телеметрия** | 24 твика | DiagTrack, CEIP, Advertising ID, журнал активности, Cortana, поиск Bing, реклама на экране блокировки, Copilot, Windows Recall, телеметрия Edge, OneDrive автозапуск |
| ⚡ **Производительность** | 13 твиков | Визуальные эффекты, прозрачность, SysMain, Search indexer, NDU, NTFS lastaccess, быстрый запуск, GPU TDR, задержка меню |
| 🎮 **Геймерское** | 7 твиков | GameDVR, FullscreenOptimizations, HAGS, ускорение мыши, MMCSS, Nagle's algorithm |
| 🌐 **Сеть** | 6 твиков | NetBIOS, LLMNR, network throttling, TCP autotuning, IPv6, Cloudflare DNS |
| 🪟 **UI / Проводник** | 10 твиков | Показ расширений, скрытые файлы, классическое контекстное меню Win11, иконки слева, скрыть виджеты/чат/новости |
| 🗑️ **Дебloat (Appx)** | 30 пакетов | Cortana, Xbox, OneDrive, Copilot, Teams (потребительский), Skype, Почта, Карты, Solitaire, Bing Погода/Новости, Clipchamp |
| ⚙️ **Службы** | 30 служб | DiagTrack, WSearch, SysMain, Факс, Xbox-службы, WerSvc, Remote Registry, BITS |
| 📅 **Задачи планировщика** | 5 задач | Office телеметрия, Feedback Hub, WaaSMedic |
| 📦 **Установщик ПО (winget)** | 71 программа | Chrome, Firefox, Brave, VLC, 7-Zip, Telegram, Discord, Steam, OBS, VS Code, Git, Node, Python, Spotify, ShareX |
| 🧹 **Очистка** | 8 целей | Temp, Prefetch, Delivery Optimization, CBS логи, журналы событий, миниатюры, корзина |

> Архитектура **data-driven**: каждый твик — это один JSON-объект. Добавление новых функций не трогает движок.

---

## 🛡️ Безопасность

Каждое изменение можно откатить:

1. Перед группой твиков создаётся **точка восстановления Windows**.
2. Каждая затрагиваемая ветка реестра экспортируется в `.reg` в `%AppData%\MightyBoost\Backups\<timestamp>\`.
3. Каждое применённое действие записывается в `%AppData%\MightyBoost\applied.json` вместе с рецептом undo — вкладка **Восстановление** в GUI откатывает любое одним кликом.
4. Опасные действия (удаление Edge, отключение Defender, IPv6 и т.д.) показывают подтверждение с предупреждением.
5. **Никаких подписанных бинарей** — ты видишь каждую строку, которая выполняется на твоей машине.

---

## 🖼️ Скриншоты

> _Положи скриншоты в `docs/screenshots/` (Главная, Приватность, Дебloat, Восстановление)._

---

## 🧑‍💻 Контрибьют

Большая часть проекта — данные, а не код. Чтобы добавить твик, не нужно знать PowerShell — добавь JSON-объект в `src/data/tweaks.json`:

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

И присылай PR. CI запустит PSScriptAnalyzer и валидацию JSON. Подробнее — в [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

---

## ⚙️ Локальная разработка

```powershell
git clone https://github.com/mighty-boost/mighty-boost.git
cd mighty-boost
.\boost.ps1 -Local       # использует локальные файлы вместо загрузки с GitHub
```

| Флаг | Эффект |
|---|---|
| `-Local` | Локальный режим (не качать модули с GitHub). |
| `-Branch <name>` | Брать модули с другой ветки (по умолчанию `main`). |
| `-NoElevate` | Не запрашивать админа автоматически (большинство твиков провалится). |

---

## 📜 Лицензия

MIT — см. [LICENSE](LICENSE).

---

## 🙏 Благодарности

MightyBoost вдохновлён этими отличными проектами (использованы как референсы по архитектуре и списку твиков):

- [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil)
- [hellzerg/optimizer](https://github.com/hellzerg/optimizer)
- [builtbybel/privatezilla](https://github.com/builtbybel/privatezilla)
- [HotCakeX/Harden-Windows-Security](https://github.com/HotCakeX/Harden-Windows-Security)
- [Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat)

---

⭐ Если проект пригодился — поставь звезду, это помогает находить его другим.
