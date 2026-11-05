# NOVA Recorder WP-01B.2a: session metadata and MP4 finalization
# Functions moved without implementation changes. Loaded by nova_recorder.ps1.

function Write-NovaSessionMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionFolder,

        [Parameter(Mandatory = $true)]
        [object]$AudioDevice,

        [Parameter(Mandatory = $true)]
        [double]$GainDb,

        [Parameter(Mandatory = $true)]
        [datetime]$Started,

        [Parameter(Mandatory = $true)]
        [datetime]$Ended,

        [object]$VideoDevice,

        [object]$VideoMode
    )

    $durationSeconds = [Math]::Round(
        ($Ended - $Started).TotalSeconds,
        3
    )

    $metadata = [ordered]@{
        started         = $Started.ToString("o")
        ended           = $Ended.ToString("o")
        durationSeconds = $durationSeconds

        audio = [ordered]@{
            file       = "audio.wav"
            device     = [string]$AudioDevice
            sampleRate = 48000
            channels   = 2
            bitDepth   = 16
            gainDb     = $GainDb
        }

        video = $null
    }

    if ($null -ne $VideoDevice -and $null -ne $VideoMode) {
        $metadata.video = [ordered]@{
            file   = "video.avi"
            device = [string]$VideoDevice
            codec  = [string]$VideoMode.Codec
            width  = [int]$VideoMode.Width
            height = [int]$VideoMode.Height
            fps    = [double]$VideoMode.MaxFps
        }
    }

    $jsonPath = Join-Path $SessionFolder "session.json"

    $metadata |
        ConvertTo-Json -Depth 5 |
        Set-Content -Path $jsonPath -Encoding UTF8
}


function New-NovaCombinedMp4 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionFolder,

        [int]$AudioDelayMs = 300
    )

    $audioPath = Join-Path $SessionFolder "audio.wav"
    $videoPath = Join-Path $SessionFolder "video.avi"
    $outputPath = Join-Path $SessionFolder "combined.mp4"

    if (-not (Test-Path -LiteralPath $audioPath)) {
        throw "Audio source not found: $audioPath"
    }

    if (-not (Test-Path -LiteralPath $videoPath)) {
        throw "Video source not found: $videoPath"
    }

    $audioFilter =
        "adelay=$AudioDelayMs|$AudioDelayMs,apad"

    $arguments = @(
        '-hide_banner'
        '-loglevel', 'warning'
        '-i', ('"' + $videoPath + '"')
        '-i', ('"' + $audioPath + '"')
        '-af', ('"' + $audioFilter + '"')
        '-c:v', 'libx264'
        '-preset', 'fast'
        '-crf', '20'
        '-c:a', 'aac'
        '-b:a', '192k'
        '-shortest'
        '-y'
        ('"' + $outputPath + '"')
    )

    $arguments = $arguments -join ' '

    $process = Start-Process `
        -FilePath $ffmpegPath `
        -ArgumentList $arguments `
        -NoNewWindow `
        -Wait `
        -PassThru

    if ($process.ExitCode -ne 0) {
        throw "FFmpeg failed to create combined.mp4 (exit code $($process.ExitCode))."
    }

    return $outputPath
}
