# NOVA Recorder WP-01B.1: extracted session/device helper functions.
# Dot-sourced by nova_recorder.ps1 after paths and application state initialize.
# The function implementations below are unchanged from WP-01A.

function New-NovaRecordingSession {
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

    $sessionFolder = Join-Path `
        $recordingsDirectory `
        "Recording_$timestamp"

    New-Item `
        -ItemType Directory `
        -Path $sessionFolder `
        -Force | Out-Null

    return $sessionFolder
}




function Get-NewRecordingPath {

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

    $sessionFolder = Join-Path `
        $recordingsDirectory `
        "Recording_$timestamp"

    New-Item `
        -ItemType Directory `
        -Path $sessionFolder `
        -Force | Out-Null

    return Join-Path $sessionFolder "audio.wav"
}


function Get-VideoRecordingPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AudioPath
    )

    $directory = Split-Path -Parent $AudioPath

    return Join-Path $directory "video.avi"
}


function Get-NovaVideoDevices {

    if (-not $script:ffmpegAvailable) {
        return @()
    }

    # FFmpeg writes DirectShow enumeration to stderr. Merge stderr into
    # stdout so PowerShell can parse it without showing a console window.
    $lines = & $ffmpegPath -hide_banner -list_devices true -f dshow -i dummy 2>&1

    $devices = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        $text = [string]$line

        # Only expose devices FFmpeg explicitly identifies as video.
        # The built-in HP camera on this machine enumerates as "(none)"
        # and cannot currently bind through DirectShow, so it is excluded.
        if ($text -match '"([^"]+)"\s+\(video\)') {
            $name = $matches[1]

            if (-not $devices.Contains($name)) {
                $devices.Add($name)
            }
        }
    }

    return $devices.ToArray()
}

function Get-NovaVideoModes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceName
    )

    if (-not $script:ffmpegAvailable) {
        return @()
    }

    $lines = & $ffmpegPath `
        -hide_banner `
        -f dshow `
        -list_options true `
        -i ('video=' + $DeviceName) 2>&1

    $modes = New-Object System.Collections.Generic.List[object]

    foreach ($line in $lines) {
        $text = [string]$line

        # Prefer native MJPEG modes because we can stream-copy them
        # during capture without expensive real-time re-encoding.
        if ($text -match 'vcodec=mjpeg\s+min s=(\d+)x(\d+)\s+fps=([\d\.]+)\s+max s=\d+x\d+\s+fps=([\d\.]+)') {

            $width  = [int]$matches[1]
            $height = [int]$matches[2]
            $minFps = [double]$matches[3]
            $maxFps = [double]$matches[4]

            $key = "$width`x$height@$maxFps"

            $alreadyExists = $false

            foreach ($existing in $modes) {
                if ($existing.Key -eq $key) {
                    $alreadyExists = $true
                    break
                }
            }

            if (-not $alreadyExists) {
                $modes.Add(
                    [PSCustomObject]@{
                        Key       = $key
                        Codec     = 'mjpeg'
                        Width     = $width
                        Height    = $height
                        MinFps    = $minFps
                        MaxFps    = $maxFps
                        Display   = "$width x $height @ $maxFps fps"
                    }
                )
            }
        }
    }

    return @(
        $modes |
        Sort-Object `
            @{ Expression = { $_.Width * $_.Height }; Descending = $true },
            @{ Expression = { $_.MaxFps }; Descending = $true }
    )
}


function Get-NovaAudioDeviceNames {
    if (-not $script:ffmpegAvailable) {
        return @()
    }

    $lines = & $ffmpegPath `
        -hide_banner `
        -list_devices true `
        -f dshow `
        -i dummy 2>&1

    $names = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        $text = [string]$line

        if ($text -match '"([^"]+)"\s+\(audio\)') {
            $name = $matches[1]

            if (-not $names.Contains($name)) {
                $names.Add($name)
            }
        }
    }

    return @($names)
}

function ConvertTo-NovaDeviceMatchKey {
    param(
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return ""
    }

    return (
        $Name.ToLowerInvariant() `
            -replace '[^a-z0-9 ]', '' `
            -replace '\s+', ' '
    ).Trim()
}
