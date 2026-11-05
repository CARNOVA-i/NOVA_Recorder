# WP-01B.2b-I1: video capture and idle preview lifecycle.
# Dot-sourced after application state initialization and before UI creation.
# PreviewTarget is supplied by the WinForms adapter; no implicit UI lookup.

function Start-NovaVideoCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceName,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [object]$Mode,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.PictureBox]$PreviewTarget
    )

    if (-not $script:ffmpegAvailable) {
        throw "Portable FFmpeg was not found at:`n$ffmpegPath"
    }

    if ($script:videoRecording) {
        throw "Video capture is already running."
    }

    $videoSize = "$($Mode.Width)x$($Mode.Height)"
    $frameRate = [string]$Mode.MaxFps
    $codec     = [string]$Mode.Codec

    # Capture the selected camera's native MJPEG mode without real-time
    # H.264 transcoding. This keeps CPU load low and minimizes frame loss.
    $arguments = @(
        '-hide_banner'
        '-loglevel', 'warning'
        '-f', 'dshow'
        '-rtbufsize', '256M'
        '-video_size', $videoSize
        '-framerate', $frameRate
        '-vcodec', $codec
        '-i', ('video="' + $DeviceName + '"')
        '-progress', 'pipe:2'
        '-stats_period', '0.05'
        '-nostats'
        '-y'
        '-map', '0:v:0'
        '-c:v', 'copy'
        '-f', 'avi'
        ('"' + $OutputPath + '"')
        '-map', '0:v:0'
        '-c:v', 'copy'
        '-f', 'image2pipe'
        'pipe:1'
    ) -join ' '

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $ffmpegPath
    $startInfo.Arguments = $arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.RedirectStandardOutput = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    if (-not $process.Start()) {
        throw "FFmpeg could not start video capture."
    }

    $script:videoReadyMonitor =
        New-Object NovaFfmpegReadyMonitor -ArgumentList $process

    $script:videoReadyMonitor.Start()

    # Drain the second MJPEG output immediately so stdout cannot block AVI writing.
    $script:recordingPreviewReader =
        New-Object NovaPreviewReader -ArgumentList $process, $PreviewTarget
    $script:recordingPreviewReader.Start()

    # Give DirectShow a moment to bind the camera. If FFmpeg exits
    # immediately, surface that as a failed start instead of pretending
    # video is recording.
    Start-Sleep -Milliseconds 350

    if ($process.HasExited) {
        if ($null -ne $script:recordingPreviewReader) {
            $script:recordingPreviewReader.Dispose()
            $script:recordingPreviewReader = $null
        }
        $exitCode = $process.ExitCode

        if ($null -ne $script:videoReadyMonitor) {
            $script:videoReadyMonitor.Dispose()
            $script:videoReadyMonitor = $null
        }

        $process.Dispose()
        throw "FFmpeg exited before video capture started (exit code $exitCode)."
    }

    $script:videoProcess = $process
    $script:videoRecording = $true
}

function Start-NovaVideoPreview {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceName,

        [Parameter(Mandatory = $true)]
        [object]$Mode,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.PictureBox]$PreviewTarget
    )

    if ($script:previewRunning) {
        return
    }

    $videoSize = "$($Mode.Width)x$($Mode.Height)"
    $frameRate = [string]$Mode.MaxFps
    $codec     = [string]$Mode.Codec

    $arguments = @(
        '-hide_banner'
        '-loglevel', 'error'
        '-f', 'dshow'
        '-rtbufsize', '128M'
        '-video_size', $videoSize
        '-framerate', $frameRate
        '-vcodec', $codec
        '-i', ('video="' + $DeviceName + '"')
        '-f', 'image2pipe'
        '-c:v', 'mjpeg'
        'pipe:1'
    ) -join ' '

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $ffmpegPath
    $startInfo.Arguments = $arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    if (-not $process.Start()) {
        throw "FFmpeg could not start camera preview."
    }

    $script:previewProcess = $process
    $script:previewRunning = $true

    $script:previewReader =
        New-Object NovaPreviewReader -ArgumentList $process, $PreviewTarget

    $script:previewReader.Start()
}

function Stop-NovaVideoPreview {

    if ($null -ne $script:previewReader) {
        $script:previewReader.Dispose()
        $script:previewReader = $null
    }

    $process = $script:previewProcess

    Write-Host "Stopping preview..."

    if ($null -ne $process) {
        Write-Host "Preview PID: $($process.Id)"
    }
    else {
        Write-Host "Preview process is null."
    }

    try {
        if ($null -ne $process -and -not $process.HasExited) {

            $process.Kill()

            if (-not $process.WaitForExit(12000)) {
                throw "Preview FFmpeg did not exit cleanly."
            }

            Write-Host "Preview HasExited: $($process.HasExited)"
        }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }

        $script:previewProcess = $null
        $script:previewRunning = $false
    }
}

function Stop-NovaVideoCapture {

    if (-not $script:videoRecording) {
        return
    }

    $process = $script:videoProcess

    try {
        if ($null -ne $process -and -not $process.HasExited) {
            # 'q' requests FFmpeg's normal shutdown path so AVI indexes and
            # headers are finalized cleanly.
            $process.StandardInput.WriteLine('q')
            $process.StandardInput.Flush()

            if (-not $process.WaitForExit(5000)) {
                $process.Kill()
                [void]$process.WaitForExit(2000)
            }
        }
    }
    finally {

        if ($null -ne $script:recordingPreviewReader) {
            $script:recordingPreviewReader.Dispose()
            $script:recordingPreviewReader = $null
        }

        if ($null -ne $script:videoReadyMonitor) {
            $script:videoReadyMonitor.Dispose()
            $script:videoReadyMonitor = $null
        }

        if ($null -ne $process) {
            $process.Dispose()
        }

        $script:videoProcess = $null
        $script:videoRecording = $false
    }
}
