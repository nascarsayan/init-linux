#Requires AutoHotkey v2.0
#SingleInstance Force

; Focus app if already running, otherwise launch it
FocusOrRun(process, command) {
    if WinExist("ahk_exe " . process)
        WinActivate("ahk_exe " . process)
    else
        Run(command)
}

; ── Window ────────────────────────────────────────────────────────────────────
#q:: WinClose("A")                              ; Win+Q         close window

; ── App launchers ─────────────────────────────────────────────────────────────
#Enter::  FocusOrRun("WindowsTerminal.exe", "wt.exe")
#+b::     FocusOrRun("msedge.exe",          "https://")
#+f::     FocusOrRun("firefox.exe",         "C:\Program Files\Mozilla Firefox\firefox.exe")
#+e:: {                                         ; Win+Shift+E   explorer (any window)
    if WinExist("ahk_class CabinetWClass")
        WinActivate("ahk_class CabinetWClass")
    else
        Run("explorer.exe")
}
#+m::     FocusOrRun("olk.exe",             "shell:AppsFolder\Microsoft.OutlookForWindows_8wekyb3d8bbwe!Microsoft.OutlookforWindows")
#!s::     FocusOrRun("slack.exe",           "C:\Users\sayann\AppData\Local\slack\slack.exe")
#+t::     FocusOrRun("ms-teams.exe",        "C:\Users\sayann\AppData\Local\Microsoft\WindowsApps\ms-teams.exe")
#+c::     FocusOrRun("Code.exe",            "code.exe")
#+a::     FocusOrRun("ChatGPT.exe",         "shell:AppsFolder\OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0!ChatGPT")

; ── Window cycling ────────────────────────────────────────────────────────────
!`:: {                                          ; Alt+`         cycle same app (macOS-style)
    activeHwnd := WinGetID("A")
    activeExe  := WinGetProcessName("A")

    all := WinGetList("ahk_exe " activeExe)
    visible := []
    for hwnd in all {
        if WinGetMinMax("ahk_id " hwnd) != -1
            visible.Push(hwnd)
    }

    if visible.Length < 2
        return

    for i, hwnd in visible {
        if hwnd = activeHwnd {
            WinActivate("ahk_id " visible[Mod(i, visible.Length) + 1])
            return
        }
    }
    WinActivate("ahk_id " visible[1])
}

; ── Cheat sheet ───────────────────────────────────────────────────────────────
#k:: {
    cs := Gui("+AlwaysOnTop", "Keyboard Shortcuts")
    cs.SetFont("s10", "Consolas")
    cs.BackColor := "1e1e2e"
    cs.Add("Text", "cdfdfff w440", "
(
  WINDOW
  Win + Q / Alt+F4       Close window
  Alt + ``               Cycle same app (macOS-style)

  APP LAUNCHERS
  Win + Enter            Terminal
  Win + Shift + B        Browser (Edge)
  Win + Shift + F        Firefox
  Win + Shift + E        Files
  Win + Shift + M        Outlook
  Win + Alt  + S         Slack
  Win + Shift + T        Teams
  Win + Shift + C        VS Code
  Win + Shift + A        ChatGPT

  SYSTEM
  Win + K                This cheat sheet
  Win + L                Lock screen
)")
    cs.Show("AutoSize")
}
