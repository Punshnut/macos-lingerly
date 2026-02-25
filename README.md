# Lingerly

Lingerly is a calm macOS menu bar companion that helps you rest your eyes without breaking momentum. It runs quietly in the background, prompts you at the right time, and stays out of the way when you are focused. The interface is intentionally clean and modern, with the most important controls exactly where you expect them in the menu bar panel. Lingerly ships as a fast native universal app for Apple Silicon and Intel Macs: minimal, focused, and open source.

<p align="center">
  <img src="https://img.shields.io/badge/macOS-native-000000?style=flat&logo=apple" alt="macOS native">
  <img src="https://img.shields.io/badge/Stage-Beta-yellow" alt="Stage Beta">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT">
  <img src="https://img.shields.io/badge/Swift-6.2.1-orange" alt="Swift 6.2.1">
</p>

<p align="center">
    <a href="https://github.com/Punshnut/macos-lingerly/releases/latest">
    <img src="https://img.shields.io/badge/Download-0.3.1-blueviolet?style=for-the-badge" alt="Download 0.3.1">
  </a>
</p>

<p align="center">
  <img src="Media/Lingerly_Logo.png" alt="Lingerly logo" width="260">
</p>

<div align="center">
  <details>
    <summary>🇪🇸 🇮🇹 🇩🇪 🇫🇷 🇵🇹 🇺🇦 🇷🇺 🇵🇱 🇬🇷 🇳🇱 🇸🇪 🇨🇿 🇭🇺 🇪🇸 🇫🇮 🇮🇪 Europe (16)</summary>
    <p>🇪🇸 Español (España)<br>🇮🇹 Italiano<br>🇩🇪 Deutsch<br>🇫🇷 Français<br>🇵🇹 Português (Portugal)<br>🇺🇦 Українська<br>🇷🇺 Русский<br>🇵🇱 Polski<br>🇬🇷 Ελληνικά<br>🇳🇱 Nederlands<br>🇸🇪 Svenska<br>🇨🇿 Čeština<br>🇭🇺 Magyar<br>🇪🇸 Català<br>🇫🇮 Suomi<br>🇮🇪 Gaeilge</p>
  </details>
  <details>
    <summary>🇵🇭 🇮🇳 🇮🇩 🇻🇳 🇹🇷 🇨🇳 🇯🇵 🇰🇷 🇹🇭 🇧🇩 🇵🇰 🇮🇳 🇮🇳 🇲🇾 🇲🇲 Asia (15)</summary>
    <p>🇵🇭 Filipino / Tagalog<br>🇮🇳 हिन्दी<br>🇮🇩 Bahasa Indonesia<br>🇻🇳 Tiếng Việt<br>🇹🇷 Türkçe<br>🇨🇳 中文（简体）<br>🇯🇵 日本語<br>🇰🇷 한국어 (대한민국)<br>🇹🇭 ภาษาไทย<br>🇧🇩 বাংলা<br>🇵🇰 اُردُو<br>🇮🇳 தமிழ்<br>🇮🇳 తెలుగు<br>🇲🇾 Bahasa Melayu<br>🇲🇲 မြန်မာ</p>
  </details>
  <details>
    <summary>🇧🇷 🇲🇽 🇺🇸 Americas (3)</summary>
    <p>🇧🇷 Português (Brasil)<br>🇲🇽 Español (LatAm)<br>🇺🇸 English</p>
  </details>
  <details>
    <summary>🇦🇪 🇮🇷 🇹🇿 🇳🇬 🇪🇹 🇳🇬 Middle East & Africa (6)</summary>
    <p>🇦🇪 العربية (الفصحى الحديثة)<br>🇮🇷 فارسی<br>🇹🇿 Kiswahili<br>🇳🇬 Hausa<br>🇪🇹 አማርኛ<br>🇳🇬 Yorùbá</p>
  </details>
</div>
<p align="center">
  <sub>Localization translations are being added soon, right now they are english placeholders!</sub>
</p>

<p align="center">
  <img src="Media/Lingerly_Screenshot.png" alt="Lingerly Screenshot" width="600">
</p>

## Highlights

- **Gentle reminders** - Soft break prompts designed to support focus, not disrupt it.
- **Simple, polished interface** - A clean menu bar panel with a modern look and low visual noise.
- **Important controls in the right place** - Start/Pause, quick time shifts (`-15` to `+15`), presets, and break actions are all one click away.
- **Menu bar first** - Menu bar only; the Dock stays clean.
- **Fullscreen respect** - Avoids interrupting fullscreen, using notifications when needed.
- **Smart Pause awareness** - Can pause around media, selected apps, and schedules, then resume with your chosen behavior.
- **Muted mode** - Keeps timing active while suppressing overlays, notifications, and sounds.
- **Hold-to-skip** - Skip only by holding space or click-and-hold; no accidental dismissals.
- **Optional lock screen** - Lock Screen appears only when you choose it.
- **Shortcuts ready** - Automate actions via Apple Shortcuts (pause, resume, skip, snooze, reset).
- **Clear status icon** - Simple visual state language in the menu bar.
- **Presets + custom** - Start with presets, then fine-tune.
- **Privacy by design** - No tracking, no accounts, stats stay on-device.
- **Universal & smooth** - Native universal build for Intel and Apple Silicon.
- **Open source & MIT** - Open source under MIT.

## Focus that just works

- **Active-time mode** - The timer advances only while you are active and unlocked.
- **Interval mode** - Optional fixed cadence every X minutes.
- **Scheduled times** - Trigger breaks at specific clock times.
- **Smart Pause sources** - Pause automatically for media playback, selected apps, or configured schedule windows.
- **Resume behavior control** - Choose whether start/resume continues the timer or resets it after Smart Pause.
- **Combinations** - Combine modes and pause logic to match your workflow.

## Gestures (touchpad or mouse)

- **Hold to skip** by press-and-hold anywhere on the overlay.
- **Tap lock screen** if you’ve enabled the optional action.
- **No gestures required** to keep Lingerly calm and lightweight.

## Keyboard shortcuts

- **Menu bar control:** Start/Stop, Snooze, Settings, and Quit from the menu bar.
- **Skip a break:** hold `Space` while the overlay is up.
- **Configurable hotkeys:** assign global shortcuts for start/stop, reset, and quick actions.

## Automations (Shortcuts)

- **Shortcuts actions:** Pause timer, Resume timer, Skip break, Snooze break, Reset timer.
- **Where to find them:** Shortcuts app → Lingerly.
- **Best for:** scheduled workflows, focus sessions, and quick menu bar triggers.

## Quick tips

- **Choose a preset** to get started fast, then customize as needed.
- **Keep fullscreen safe** if you are presenting or recording.
- **Use snooze** for short interruptions instead of turning Lingerly off.
- **Use Muted mode** when you want full suppression but still want timing rhythm preserved.
- **Enable lock screen** only if you want a firm, explicit action.
- **Keep it quiet** - Lingerly is designed to fade into the background between breaks.

## License & support

- **License:** MIT. Use it anywhere; just keep the notice.

## Roadmap

Here are a few improvements planned for upcoming releases:
- **Smarter rhythms** - adaptive break timing based on real activity
- **Better overlays** - calmer visuals and richer accessibility options
- **Sound cues (optional)** - subtle, non-distracting sounds with configurable sound options (kept minimal by default)

[Donate (Ko-Fi)](https://ko-fi.com/janfeuerbacher)

Made with ❤️

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Punshnut/macos-lingerly&type=date&legend=top-left)](https://www.star-history.com/#Punshnut/macos-lingerly&type=date&legend=top-left)
