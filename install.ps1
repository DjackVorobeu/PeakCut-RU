# PeakCut — установка на Windows без прав администратора.
# Запуск:  powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
# Параметры: -Folder C:\peakcut  -NoModels (не скачивать модели речи)  -NoShortcut
param(
    [string]$Folder = "C:\peakcut",
    [switch]$NoModels,
    [switch]$NoShortcut
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$RepoZip = "https://codeload.github.com/DjackVorobeu/PeakCut-RU/zip/refs/heads/main"

function Say($text) { Write-Host "  $text" }
function Step($text) { Write-Host ""; Write-Host "== $text" -ForegroundColor White }

function Get-ScriptFolder { Split-Path -Parent $MyInvocation.ScriptName }

# 1. Где взять файлы программы: эта папка, если в ней уже лежит requirements.txt
$here = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $PSScriptRoot "requirements.txt"))) {
    Step "Скачиваю PeakCut в $Folder"
    $zip = Join-Path $env:TEMP "peakcut.zip"
    Invoke-WebRequest -Uri $RepoZip -OutFile $zip -UseBasicParsing
    $tmp = Join-Path $env:TEMP ("peakcut-unzip-" + [guid]::NewGuid().ToString("N"))
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $inner = (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName
    New-Item -ItemType Directory -Force -Path $Folder | Out-Null
    Copy-Item (Join-Path $inner "*") $Folder -Recurse -Force
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    $here = $Folder
} else {
    $here = $PSScriptRoot
}
Say "Папка программы: $here"

# 2. Python 3.10+
Step "Проверяю Python"
function Find-Python {
    foreach ($cand in @("py -3.12", "py -3", "python")) {
        $parts = $cand.Split(" ")
        $exe = Get-Command $parts[0] -ErrorAction SilentlyContinue
        if (-not $exe) { continue }
        $args = @()
        if ($parts.Count -gt 1) { $args += $parts[1..($parts.Count - 1)] }
        try {
            $out = & $exe.Source @args -c "import sys; print(sys.version_info[0], sys.version_info[1])" 2>$null
            $line = ($out | Out-String).Trim()
            if ($line -match "^(\d+) (\d+)$") {
                $maj = [int]$Matches[1]; $min = [int]$Matches[2]
                if ($maj -eq 3 -and $min -ge 10) { return @($exe.Source) + $args }
            }
        } catch { }
    }
    return $null
}

$py = Find-Python
if (-not $py) {
    Say "Python не найден, ставлю Python 3.12 (в профиль пользователя)"
    $wg = Get-Command winget -ErrorAction SilentlyContinue
    if ($wg) {
        & winget install --id Python.Python.3.12 --exact --scope user --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    } else {
        $exe = Join-Path $env:TEMP "python-3.12.10-amd64.exe"
        Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe" -OutFile $exe -UseBasicParsing
        Start-Process -FilePath $exe -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1" -Wait
    }
    $env:PATH = "$env:LOCALAPPDATA\Programs\Python\Python312;$env:LOCALAPPDATA\Programs\Python\Python312\Scripts;" + $env:PATH
    $py = Find-Python
    if (-not $py) { throw "Python не установился. Поставьте его с python.org и запустите установщик снова." }
}
Say ("Python: " + (& $py[0] @($py[1..($py.Count - 1)]) --version 2>&1))

# 3. ffmpeg
Step "Проверяю ffmpeg"
$bin = Join-Path $here "bin"
New-Item -ItemType Directory -Force -Path $bin | Out-Null
if (-not (Test-Path (Join-Path $bin "ffmpeg.exe"))) {
    Say "Скачиваю ffmpeg (~200 МБ)"
    $zip = Join-Path $env:TEMP "ffmpeg.zip"
    & curl.exe -L --fail --connect-timeout 30 --max-time 900 -o $zip "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
    if ($LASTEXITCODE -ne 0) { throw "Не удалось скачать ffmpeg. Проверьте интернет и запустите снова." }
    $x = Join-Path $env:TEMP ("ffmpeg-x-" + [guid]::NewGuid().ToString("N"))
    Expand-Archive -Path $zip -DestinationPath $x -Force
    $f = Get-ChildItem $x -Recurse -Filter ffmpeg.exe | Select-Object -First 1
    Copy-Item $f.FullName (Join-Path $bin "ffmpeg.exe") -Force
    Copy-Item (Join-Path $f.DirectoryName "ffprobe.exe") (Join-Path $bin "ffprobe.exe") -Force
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Remove-Item $x -Recurse -Force -ErrorAction SilentlyContinue
}
$env:PATH = "$bin;$env:PATH"
Say "ffmpeg на месте"

# 4. Окружение Python и зависимости
Step "Ставлю зависимости"
$venvPy = Join-Path $here ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPy)) { & $py[0] @($py[1..($py.Count - 1)]) -m venv (Join-Path $here ".venv") }
& $venvPy -m pip install --upgrade pip --quiet
& $venvPy -m pip install -r (Join-Path $here "requirements.txt")
if ($LASTEXITCODE -ne 0) { throw "Зависимости не установились. Проверьте интернет и запустите снова." }

# 5. Модели речи (английская нужна всегда, русская — для русской речи)
if (-not $NoModels) {
    Step "Скачиваю модели речи (около 850 МБ, один раз)"
    Push-Location $here
    try {
        & $venvPy -m studio.fetch_model
        & $venvPy -m studio.fetch_model ru
    } finally { Pop-Location }
}

# 6. Запускатор и ярлык
Step "Готовлю запуск"
$exe = Join-Path $here "PeakCut.exe"
$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $exe)) {
    if ((Test-Path $csc) -and (Test-Path (Join-Path $here "Launcher.cs"))) {
        & $csc /nologo /target:winexe /optimize+ ("/out:" + $exe) (Join-Path $here "Launcher.cs") | Out-Null
        Say "Собран PeakCut.exe"
    } else {
        $exe = $venvPy
    }
}
if (-not $NoShortcut) {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut((Join-Path $desktop "PeakCut.lnk"))
    $lnk.TargetPath = $exe
    $lnk.WorkingDirectory = $here
    $ico = Join-Path $here "assets\peakcut.ico"
    if (Test-Path $ico) { $lnk.IconLocation = "$ico,0" }
    $lnk.Description = "PeakCut - клипы из длинных видео"
    $lnk.Save()
    Say "Ярлык PeakCut создан на Рабочем столе"
}

Step "Готово"
Say "Запуск: ярлык PeakCut на Рабочем столе (или $exe)."
Say "Программа откроется в браузере: http://127.0.0.1:8765"
Say "Остановить: Stop-PeakCut.cmd в этой папке."
if (-not $NoShortcut) { Start-Process -FilePath $exe -WorkingDirectory $here }
