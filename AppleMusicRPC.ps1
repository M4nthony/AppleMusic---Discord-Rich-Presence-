# AppleMusicRPC - shows what you're playing in Apple Music (Windows) as your Discord status.
# Reads the song from Windows' media controls and sends it to Discord's official status connection.
# Runs hidden in the background. Log: %APPDATA%\AppleMusicRPC\log.txt

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = Join-Path $dir 'log.txt'
function Log([string]$msg) {
    try { "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg" | Out-File -FilePath $logFile -Append -Encoding utf8 } catch {}
}
if ((Test-Path $logFile) -and ((Get-Item $logFile).Length -gt 200KB)) { Remove-Item $logFile -Force }

# Only one copy at a time
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\AppleMusicRPC', [ref]$created)
if (-not $created) { exit }

# ---------- settings ----------
$cfgFile = Join-Path $dir 'config.json'
if (-not (Test-Path $cfgFile)) { Log 'config.json missing, run install.bat again'; exit }
$cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json
$AppId = [string]$cfg.appId
$ShowPaused = [bool]$cfg.showPaused
$ShowButton = [bool]$cfg.showButton
Log "Started (App ID $AppId)"

# ---------- Windows media controls ----------
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]
function Await($op, [Type]$type) {
    $task = $asTaskGeneric.MakeGenericMethod($type).Invoke($null, @($op))
    $task.Wait(-1) | Out-Null
    $task.Result
}
[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime] | Out-Null
$mgrType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]
$propsType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties]
$manager = Await ($mgrType::RequestAsync()) $mgrType

function Get-Track {
    foreach ($s in $manager.GetSessions()) {
        $id = [string]$s.SourceAppUserModelId
        if ($id -notlike '*AppleMusic*' -and $id -notlike '*iTunes*') { continue }

        $p = Await ($s.TryGetMediaPropertiesAsync()) $propsType
        if (-not $p -or -not $p.Title) { return $null }
        $t = $s.GetTimelineProperties()
        $status = [string]$s.GetPlaybackInfo().PlaybackStatus

        $artist = [string]$p.Artist
        $album = [string]$p.AlbumTitle
        # Apple Music for Windows often puts "Artist — Album" together in the artist field
        if (-not $album -and $artist -match '\s[—–-]\s') {
            $parts = $artist -split '\s[—–-]\s', 2
            $artist = $parts[0]; $album = $parts[1]
        }

        $pos = $t.Position.TotalSeconds
        $playing = ($status -eq 'Playing')
        if ($playing) {
            $since = ([DateTimeOffset]::UtcNow - $t.LastUpdatedTime).TotalSeconds
            if ($since -gt 0 -and $since -lt 36000) { $pos += $since }
        }
        $dur = $t.EndTime.TotalSeconds
        if ($dur -gt 0 -and $pos -gt $dur) { $pos = $dur }

        return [pscustomobject]@{
            title = [string]$p.Title; artist = $artist; album = $album
            status = $status; playing = $playing; pos = $pos; dur = $dur
        }
    }
    return $null
}

# ---------- album cover + link from Apple's public catalog ----------
$artCache = @{}
function Clean-Title([string]$t) {
    # "drugr4ts (feat. someone)" -> "drugr4ts", "Song - Remastered 2011" -> "Song"
    $t = $t -replace '\s*[\(\[][^\)\]]*(feat|ft\.|with|remaster|version|edit|live|mix)[^\)\]]*[\)\]]', ''
    $t = $t -replace '\s+-\s+.*(remaster|version|edit|live|mix).*$', ''
    return $t.Trim()
}
function Get-Art([string]$title, [string]$artist) {
    $key = "$title|$artist".ToLower()
    if ($artCache.ContainsKey($key)) { return $artCache[$key] }
    $res = @{ art = $null; url = $null }
    $clean = Clean-Title $title
    $searches = @("$artist $title", "$artist $clean", $clean) | Where-Object { $_.Trim() } | Select-Object -Unique
    foreach ($country in @('PH', 'US')) {
        foreach ($term in $searches) {
            try {
                $q = [uri]::EscapeDataString($term.Trim())
                $r = Invoke-RestMethod -Uri "https://itunes.apple.com/search?term=$q&entity=song&limit=5&country=$country" -TimeoutSec 5
                if ($r.resultCount -gt 0) {
                    # Prefer a result by the same artist
                    $hit = $r.results | Where-Object { $artist -and ($_.artistName -like "*$artist*" -or $artist -like "*$($_.artistName)*") } | Select-Object -First 1
                    if (-not $hit) { $hit = $r.results[0] }
                    $res.art = ([string]$hit.artworkUrl100) -replace '100x100bb', '512x512bb'
                    $res.url = [string]$hit.trackViewUrl
                    Log "Cover found for '$title' (search: $term, store: $country)"
                    break
                }
            } catch { Log "Cover lookup failed: $($_.Exception.Message)" }
        }
        if ($res.art) { break }
    }
    if (-not $res.art) { Log "No cover found for '$title' by '$artist'" }
    if ($artCache.Count -gt 200) { $artCache.Clear() }
    $artCache[$key] = $res
    return $res
}

# ---------- Discord connection ----------
function Send-Frame($pipe, [int]$op, [string]$json) {
    $body = [Text.Encoding]::UTF8.GetBytes($json)
    $buf = New-Object byte[] (8 + $body.Length)
    [BitConverter]::GetBytes([int32]$op).CopyTo($buf, 0)
    [BitConverter]::GetBytes([int32]$body.Length).CopyTo($buf, 4)
    $body.CopyTo($buf, 8)
    $pipe.Write($buf, 0, $buf.Length)
    $pipe.Flush()
}
function Read-Exact($pipe, [int]$n) {
    $b = New-Object byte[] $n
    $o = 0
    while ($o -lt $n) {
        $r = $pipe.Read($b, $o, $n - $o)
        if ($r -le 0) { throw 'Discord closed the connection' }
        $o += $r
    }
    return , $b
}
function Read-Frame($pipe) {
    $h = Read-Exact $pipe 8
    $len = [BitConverter]::ToInt32($h, 4)
    if ($len -le 0) { return '' }
    $b = Read-Exact $pipe $len
    return [Text.Encoding]::UTF8.GetString($b)
}
function Connect-Discord {
    for ($i = 0; $i -le 9; $i++) {
        $p = $null
        try {
            $p = New-Object System.IO.Pipes.NamedPipeClientStream('.', "discord-ipc-$i", [System.IO.Pipes.PipeDirection]::InOut)
            $p.Connect(500)
            Send-Frame $p 0 (@{ v = 1; client_id = $AppId } | ConvertTo-Json -Compress)
            $reply = Read-Frame $p
            if ($reply -match '"READY"') { Log "Connected to Discord"; return $p }
            Log "Discord refused the connection: $reply"
            $p.Dispose()
        } catch {
            if ($p) { $p.Dispose() }
        }
    }
    return $null
}
function Set-Activity($pipe, $activity) {
    $payload = @{
        cmd = 'SET_ACTIVITY'
        args = @{ pid = $PID; activity = $activity }
        nonce = [guid]::NewGuid().ToString()
    }
    Send-Frame $pipe 1 ($payload | ConvertTo-Json -Depth 8 -Compress)
    $reply = Read-Frame $pipe
    if ($reply -match '"evt":"ERROR"') { Log "Discord error: $reply" }
}
function Cut([string]$s, [int]$max) {
    if (-not $s) { return '' }
    if ($s.Length -lt 2) { $s = "$s " }   # Discord needs at least 2 characters
    if ($s.Length -gt $max) { return $s.Substring(0, $max) }
    return $s
}

# ---------- main loop ----------
$pipe = $null
$lastKey = ''
$lastStart = 0
$waitedForDiscord = $false

while ($true) {
    try {
        if (-not $pipe -or -not $pipe.IsConnected) {
            $pipe = Connect-Discord
            $lastKey = ''
            if (-not $pipe) {
                if (-not $waitedForDiscord) { Log 'Discord not open yet, waiting...'; $waitedForDiscord = $true }
                Start-Sleep -Seconds 10
                continue
            }
            $waitedForDiscord = $false
        }

        $tr = Get-Track
        if ($tr -and ($tr.playing -or ($ShowPaused -and $tr.status -eq 'Paused'))) {
            $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $start = [int64]($now - [math]::Floor($tr.pos))
            $key = "$($tr.title)|$($tr.artist)|$($tr.status)"
            $seeked = $tr.playing -and ([math]::Abs($start - $lastStart) -gt 3)

            if ($key -ne $lastKey -or $seeked) {
                $art = Get-Art $tr.title $tr.artist
                $state = if ($tr.artist) { $tr.artist } else { 'Unknown artist' }
                if (-not $tr.playing) { $state = "Paused - $state" }

                $act = @{
                    type = 2                  # "Listening to"
                    status_display_type = 2   # member list shows the song title instead of "Apple Music"
                    details = (Cut $tr.title 128)
                    state = (Cut $state 128)
                }
                if ($tr.playing -and $tr.dur -gt 0) {
                    $act.timestamps = @{ start = $start; end = $start + [int64][math]::Round($tr.dur) }
                }
                if ($art.art) {
                    $act.assets = @{ large_image = $art.art; large_text = (Cut ($(if ($tr.album) { $tr.album } else { $tr.title })) 128) }
                }
                if ($ShowButton -and $art.url) {
                    $act.buttons = @(@{ label = 'Listen on Apple Music'; url = $art.url })
                }

                Set-Activity $pipe $act
                Log "Now: $($tr.title) - $($tr.artist) ($($tr.status))"
                $lastKey = $key
                $lastStart = $start
            }
        } elseif ($lastKey -ne 'none') {
            Set-Activity $pipe $null
            $lastKey = 'none'
        }
    } catch {
        Log "Error: $($_.Exception.Message)"
        if ($pipe) { try { $pipe.Dispose() } catch {} }
        $pipe = $null
    }
    Start-Sleep -Seconds 2
}
