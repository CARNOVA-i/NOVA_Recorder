# WP-01B.2b-I2A: Recording start controller.
# UI-independent startup orchestration. STOP/finalization remains in the existing UI.
# The UI supplies a message-pump callback to retain the existing Windows Forms
# responsiveness while waiting for camera frames.
function Start-NovaRecording {
    param(
        [Parameter(Mandatory = $true)]
        [object]$AudioDevice,

        [Parameter(Mandatory = $true)]
        [double]$GainDb,

        [Parameter(Mandatory = $true)]
        [bool]$VideoEnabled,

        [string]$VideoDeviceName,
        [object]$VideoMode,
        [object]$PreviewTarget,
        [scriptblock]$PumpEvents,
        [scriptblock]$OnCameraStarting
    )

    if ($script:recording) {
        throw "A recording is already in progress."
    }

    if ($VideoEnabled -and (
        [string]::IsNullOrWhiteSpace($VideoDeviceName) -or
        $null -eq $VideoMode -or
        $null -eq $PreviewTarget
    )) {
        throw "Video capture requires a device, mode, and preview destination."
    }

    $script:currentFile = Get-NewRecordingPath
    $script:currentVideoFile = $null

    if ($VideoEnabled) {
        $script:currentVideoFile = Get-VideoRecordingPath -AudioPath $script:currentFile
    }

    try {
        $script:recorder.SetGainDb($GainDb)

        if ($VideoEnabled) {
            Stop-NovaVideoPreview

            # Preserve known-good DirectShow camera release delay.
            Start-Sleep -Milliseconds 3000

            $script:currentVideoMode = $VideoMode

            if ($null -ne $OnCameraStarting) {
                & $OnCameraStarting
            }

            Start-NovaVideoCapture `
                -DeviceName $VideoDeviceName `
                -OutputPath $script:currentVideoFile `
                -Mode $VideoMode `
                -PreviewTarget $PreviewTarget

            Write-Host "Recording FFmpeg PID: $($script:videoProcess.Id)"
            Write-Host "Recording FFmpeg HasExited: $($script:videoProcess.HasExited)"

            # Readiness monitor signals readiness only, not synchronization time.
            $videoReadyDeadline = (Get-Date).AddSeconds(15)

            while (
                $null -ne $script:videoReadyMonitor -and
                -not $script:videoReadyMonitor.VideoReady
            ) {
                Write-Host `
                    "Waiting for video ready... Ready=$($script:videoReadyMonitor.VideoReady) HasExited=$($script:videoProcess.HasExited)"

                if ((Get-Date) -ge $videoReadyDeadline) {
                    $videoBytes = -1

                    if (Test-Path -LiteralPath $script:currentVideoFile) {
                        $videoBytes = (Get-Item -LiteralPath $script:currentVideoFile).Length
                    }

                    Write-Host `
                        "VIDEO TIMEOUT: Ready=$($script:videoReadyMonitor.VideoReady) HasExited=$($script:videoProcess.HasExited) VideoBytes=$videoBytes"

                    throw "Camera did not begin producing video within 15 seconds."
                }

                if (
                    $null -ne $script:videoProcess -and
                    $script:videoProcess.HasExited
                ) {
                    throw "FFmpeg exited while waiting for the camera to become ready."
                }

                if ($null -ne $PumpEvents) {
                    & $PumpEvents
                }
                Start-Sleep -Milliseconds 10
            }

            if (
                $null -eq $script:videoReadyMonitor -or
                -not $script:videoReadyMonitor.VideoReady
            ) {
                throw "Camera readiness could not be confirmed."
            }
        }

        # Audio starts only after the video-ready gate succeeds.
        $script:recorder.Start($AudioDevice.Id, $script:currentFile)
    }
    catch {
        # Preserve the current atomic-start cleanup behavior.
        if ($script:videoRecording) {
            try { Stop-NovaVideoCapture } catch { }
        }
        try { $script:recorder.Stop() } catch { }
        throw
    }
}
