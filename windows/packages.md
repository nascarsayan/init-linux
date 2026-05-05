# Windows Packages

## Restore winget packages

```powershell
winget import -i winget-packages.json --accept-package-agreements --accept-source-agreements
```

---

## winget — Dev / Shell

| App | winget ID | Notes |
|-----|-----------|-------|
| Git | `Git.Git` | |
| GitHub CLI | `GitHub.cli` | |
| Node.js | `OpenJS.NodeJS` | v25 |
| PowerShell 7 | `Microsoft.PowerShell` | |
| Windows Terminal | `Microsoft.WindowsTerminal` | |
| VS Code | `Microsoft.VisualStudioCode` | |
| Zed | `ZedIndustries.Zed` | |
| gsudo | `gerardog.gsudo` | sudo for Windows |
| fzf | `junegunn.fzf` | fuzzy finder |
| zoxide | `ajeetdsouza.zoxide` | smart cd |
| Atuin | `Atuinsh.Atuin` | shell history |
| Starship | `Starship.Starship` | prompt |
| Oh My Posh | `JanDeDobbeleer.OhMyPosh` | installed, not active (using Starship) |

## winget — Apps

| App | winget ID | Notes |
|-----|-----------|-------|
| Firefox | `Mozilla.Firefox` | |
| Microsoft Edge | `Microsoft.Edge` | |
| Slack | `SlackTechnologies.Slack` | |
| Microsoft Teams | `Microsoft.Teams` | |
| Warp | `Warp.Warp` | terminal |
| OneDrive | `Microsoft.OneDrive` | |
| PowerToys | `Microsoft.PowerToys` | |
| AutoHotkey | `AutoHotkey.AutoHotkey` | v2 — hotkeys.ahk at ~ |
| AirPodsDesktop | `SpriteOvO.AirPodsDesktop` | AirPods battery/connect |

## winget — Fonts

| Font | winget ID |
|------|-----------|
| JetBrainsMono Nerd Font | `DEVCOM.JetBrainsMonoNerdFont` |

## winget — Runtimes & Frameworks

These are pulled in as dependencies but good to have explicit:

| Package | winget ID |
|---------|-----------|
| VC Redist 2015–2022 x64 | `Microsoft.VCRedist.2015+.x64` |
| VC Redist 2015–2022 x86 | `Microsoft.VCRedist.2015+.x86` |
| VCLibs 14 | `Microsoft.VCLibs.14` |
| VCLibs Desktop 14 | `Microsoft.VCLibs.Desktop.14` |
| Windows App Runtime 1.6 | `Microsoft.WindowsAppRuntime.1.6` |
| Windows App Runtime 1.7 | `Microsoft.WindowsAppRuntime.1.7` |
| Windows App Runtime 1.8 | `Microsoft.WindowsAppRuntime.1.8` |
| .NET Native Runtime | `Microsoft.DotNet.Native.Runtime` |
| UI.Xaml 2.8 | `Microsoft.UI.Xaml.2.8` |
| App Installer | `Microsoft.AppInstaller` |

---

## Microsoft Store (manual install)

These can't go in winget-packages.json — install manually from Store or with `winget install --id <store-id> --source msstore`.

| App | Store ID | Notes |
|-----|----------|-------|
| WhatsApp | `9NKSQGP7F2NH` | |
| Outlook for Windows | `9NRX63209R7B` | new Outlook app |
| OpenAI Codex | `9PLM9XGG6VKS` | |
| ChatGPT Desktop | `OpenAI.ChatGPT-Desktop` (Store) | hotkey: Win+Shift+A |

---

## Corporate / IT-managed (not reinstallable manually)

Provisioned by Cerebras IT — will be pushed automatically on domain-joined / Intune-enrolled machines.

| App | Notes |
|-----|-------|
| CrowdStrike Sensor + Device Control + Firmware Analysis | EDR/security |
| GlobalProtect 6.2.8 | Palo Alto VPN |
| Microsoft Intune Management Extension | MDM agent |
| Microsoft 365 Apps for business (Office) | Click-to-Run |
| Local AI Manager for Microsoft 365 | M365 Copilot |

---

## Pre-installed / OEM (hardware drivers)

Came with the machine — no reinstall needed; here for inventory.

| App | Source |
|-----|--------|
| Realtek Audio Control | Store (OEM) |
| Intel Arc Software | Store (OEM) |
| Dolby Access + Dolby Digital Plus Decoder | Store (OEM) |
| ELAN TrackPoint | Store (OEM) |
| Goodix Fingerprint Reader | Store (OEM) |
