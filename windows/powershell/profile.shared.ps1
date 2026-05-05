# ════════════════════════════════════════════════════════════════════════════
#  Shared PowerShell profile — works on PS 5.1 and PS 7+
#  Sourced by both:
#    ~/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1  (PS5)
#    ~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1          (PS7)
# ════════════════════════════════════════════════════════════════════════════

$_ps7 = $PSVersionTable.PSVersion.Major -ge 7

# ─── PSReadLine ──────────────────────────────────────────────────────────────
# PS7 ships with PSReadLine 2.3+. PS5 inbox version is 2.0; load the user-
# installed 2.4 from the WinPS module folder instead.
if (-not $_ps7) {
    $_psrlPath = "$HOME\Documents\WindowsPowerShell\Modules\PSReadLine"
    if (Test-Path $_psrlPath) {
        $_ver = Get-ChildItem $_psrlPath |
                Sort-Object Name -Descending |
                Select-Object -First 1 -ExpandProperty Name
        Import-Module PSReadLine -RequiredVersion $_ver -ErrorAction SilentlyContinue
    }
    Remove-Variable _psrlPath, _ver -ErrorAction SilentlyContinue
}

$_psrl = Get-Module PSReadLine

Set-PSReadLineOption -EditMode Emacs
Set-PSReadLineOption -MaximumHistoryCount 10000
Set-PSReadLineOption -HistoryNoDuplicates
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineOption -ShowToolTips
Set-PSReadLineOption -BellStyle None
Set-PSReadLineOption -HistorySavePath (Join-Path $HOME '.ps_history')

# Prediction — PSReadLine 2.1+ only, requires VT terminal
if ($_psrl.Version -ge [version]'2.1') {
    try {
        Set-PSReadLineOption -PredictionSource History
        Set-PSReadLineOption -PredictionViewStyle InlineView
        # Use [char]27 (not `e) for PS5.1 compatibility
        Set-PSReadLineOption -Colors @{ InlinePrediction = "$([char]27)[38;5;244m" }
    } catch { }
}
Remove-Variable _psrl

Set-PSReadLineOption -Colors @{
    Command   = 'Cyan'
    Parameter = 'DarkCyan'
    String    = 'Green'
    Comment   = 'DarkGray'
    Keyword   = 'Magenta'
    Error     = 'Red'
}

Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteCharOrExit
Set-PSReadLineKeyHandler -Chord UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Chord DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Chord Tab       -Function MenuComplete
Set-PSReadLineKeyHandler -Chord 'Ctrl+w'  -Function BackwardKillWord
Set-PSReadLineKeyHandler -Chord 'Ctrl+u'  -Function BackwardDeleteLine
Set-PSReadLineKeyHandler -Chord 'Ctrl+a'  -Function BeginningOfLine
Set-PSReadLineKeyHandler -Chord 'Ctrl+e'  -Function EndOfLine
Set-PSReadLineKeyHandler -Chord 'Alt+.' -ScriptBlock {
    param($key, $arg)
    $last = (Get-History -Count 1).CommandLine
    if ($last) { [Microsoft.PowerShell.PSConsoleReadLine]::Insert($last.Split()[-1]) }
}

# ─── Starship prompt ─────────────────────────────────────────────────────────
if (Get-Command starship -ErrorAction SilentlyContinue) {
    $env:STARSHIP_CONFIG = "$HOME\.config\starship.toml"
    Invoke-Expression (& starship init powershell)
}

# ─── FZF + PSFzf ─────────────────────────────────────────────────────────────
# PSFzf lives in a version-specific module folder
if ($_ps7) {
    $_psfzfDir = "$HOME\Documents\PowerShell\Modules\PSFzf"
} else {
    $_psfzfDir = "$HOME\Documents\WindowsPowerShell\Modules\PSFzf"
}

if ((Get-Command fzf -ErrorAction SilentlyContinue) -and (Test-Path $_psfzfDir)) {
    $env:FZF_DEFAULT_OPTS = '--height=40% --layout=reverse --border=rounded --info=inline'
    Import-Module PSFzf -ErrorAction SilentlyContinue
    Set-PsFzfOption -PSReadlineChordProvider       'Ctrl+t'
    Set-PsFzfOption -PSReadlineChordSetLocation    'Alt+c'
}
Remove-Variable _psfzfDir

# ─── Zoxide ──────────────────────────────────────────────────────────────────
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# ─── Atuin ───────────────────────────────────────────────────────────────────
if (Get-Command atuin -ErrorAction SilentlyContinue) {
    Invoke-Expression (& atuin init powershell --disable-up-arrow | Out-String)
}

# ─── Git branch completions ───────────────────────────────────────────────────
Register-ArgumentCompleter -Native -CommandName git -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $tokens = $commandAst.ToString().Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($tokens.Count -ge 2 -and $tokens[1] -in 'checkout','co','branch','merge','rebase','push','pull','diff','log') {
        git branch --format='%(refname:short)' 2>$null |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
}

# ─── Aliases & functions ─────────────────────────────────────────────────────
if (Get-Command eza -ErrorAction SilentlyContinue) {
    function ls { eza -lh --group-directories-first --icons=auto @args }
    function la { eza -lha --group-directories-first --icons=auto @args }
    function lt { eza --tree --icons=auto @args }
} else {
    function ls { Get-ChildItem @args }
    function la { Get-ChildItem -Force @args }
}

function mkcd {
    param([Parameter(Mandatory)][string]$dir)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Location $dir
}

function ggpush {
    $branch = git rev-parse --abbrev-ref HEAD 2>$null
    if ($branch) { git push origin $branch @args }
}
function gst   { git status @args }
function gco   { git checkout @args }
function gcb   { git checkout -b @args }
function glog  { git log --oneline --graph --decorate @args }
function gd    { git diff @args }
function ga    { git add @args }
function gcmsg { git commit -m @args }
function gp    { git pull @args }

function which  { Get-Command $args[0] -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source }
function reload { . $PROFILE }
function grep   { Select-String -Pattern $args[0] @($args | Select-Object -Skip 1) }

# ─── Environment ─────────────────────────────────────────────────────────────
$env:EDITOR = if (Get-Command nvim -ErrorAction SilentlyContinue) { 'nvim' }
              elseif (Get-Command vim -ErrorAction SilentlyContinue) { 'vim' }
              else { 'notepad' }

$env:LANG = 'en_US.UTF-8'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Remove-Variable _ps7
