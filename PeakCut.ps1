# PeakCut - starts the local server and opens the app in your browser.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root
$env:PATH = (Join-Path $root 'bin') + ';' + $env:PATH
$env:PYTHONIOENCODING = 'utf-8'
$port = 8765
$url = "http://127.0.0.1:$port/"
$data = Join-Path $root 'data'
if (-not (Test-Path $data)) { New-Item -ItemType Directory -Path $data | Out-Null }

function Test-ServerUp {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $client.Connect('127.0.0.1', $port)
        $client.Close()
        return $true
    } catch {
        return $false
    } finally {
        if ($client) { $client.Dispose() }
    }
}

if (-not (Test-ServerUp)) {
    $py = Join-Path $root '.venv\Scripts\python.exe'
    $out = Join-Path $data 'server.log'
    $err = Join-Path $data 'server-error.log'
    Start-Process -FilePath $py -ArgumentList '-m', 'studio.server' -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
    $up = $false
    for ($i = 0; $i -lt 300; $i++) {
        Start-Sleep -Milliseconds 400
        if (Test-ServerUp) { $up = $true; break }
    }
    if (-not $up) {
        Start-Process notepad.exe $err
        return
    }
}

Start-Process $url
