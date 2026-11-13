# NOVA Studio WP-02B2B-I3B-I1-R2: internal startup preflight state correction.
# Operates solely in this child process. Never dot-source nova_recorder.ps1 (it opens UI).
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$EngineRoot,
      [Parameter(Mandatory=$true)][string]$BridgeDir,
      [Parameter(Mandatory=$true)][int]$ParentPid)
$ErrorActionPreference = 'Stop'
$sequence = 0
$lastCommand = 'NONE'
$lastRequestSequence = 0
$state = 'INITIALIZING'
$errorMessage = ''
$ok = $false
$engineInitialized = $false
$recorderCreated = $false
$dependenciesLoaded = $false
$ffmpegAvailable = $false
$audioCaptureStarted = $false
$videoCaptureStarted = $false
$script:audioDevices = @()
$script:activeAudioDevice = $null
$script:activeGainDb = 0.0
$script:outputWav = ''
$script:outputSessionFolder = ''
$script:recordingStartedUtc = ''
$script:recordingError = ''
$script:finalizationOk = $false
$script:recorder = $null
$script:previewProcess = $null
$script:previewReader = $null
$script:previewDevice = ''
$script:previewMode = ''
$script:cameraModes = @()
$script:cameraDevices = @()
$script:previewError = ''
$script:previewFramePath = Join-Path $BridgeDir 'preview.jpg'
$script:recordingStudioReader = $null
$script:activeVideoDevice = ''
$script:activeVideoMode = $null
$script:activeSessionHasVideo = $false
$script:outputAvi = ''
$script:outputMp4 = ''
$script:videoReady = $false
$script:videoCaptureError = ''
$script:cameraStartupStage = ''
$script:monitorEnabled = $false # Explicit UI intent only; no capture on worker launch.
$script:monitorDeviceId = -1
$script:monitorGainDb = 0.0
$script:monitorError = ''

function Publish-State {
    $script:sequence++
    $payload = [ordered]@{
        ok=$script:ok; state=$script:state; utc=[DateTime]::UtcNow.ToString('o')
        sequence=$script:sequence; lastCommand=$script:lastCommand
        lastRequestSequence=$script:lastRequestSequence; error=$script:errorMessage
        engineInitialized=$script:engineInitialized
        recorderCreated=$script:recorderCreated
        dependenciesLoaded=$script:dependenciesLoaded
        ffmpegAvailable=$script:ffmpegAvailable
        captureEnabled=$true
        audioCaptureStarted=[bool]$script:recorder.IsRecording
        # High-resolution, post-gain sample peak from the existing recording callback.
        # GetPeakDbfs atomically consumes the interval maximum; no second capture.
        meterPeakDbfs=$(if ($script:recorder.IsRecording -or $script:recorder.IsPreviewing) { [double]$script:recorder.GetPeakDbfs() } else { -96.0 })
        meterClipped=$(if ($script:recorder.IsRecording -or $script:recorder.IsPreviewing) { [bool]$script:recorder.GetAndResetClipping() } else { $false })
        meterActive=[bool]($script:recorder.IsRecording -or $script:recorder.IsPreviewing)
        monitorActive=[bool]$script:recorder.IsPreviewing
        monitorEnabled=[bool]$script:monitorEnabled
        monitorDeviceId=[int]$script:monitorDeviceId
        monitorError=[string]$script:monitorError
        videoCaptureStarted=[bool]$script:videoRecording
        videoReady=[bool]$script:videoReady
        cameraStartupStage=$script:cameraStartupStage
        outputAvi=$script:outputAvi
        outputMp4=$script:outputMp4
        activeSessionHasVideo=[bool]$script:activeSessionHasVideo
        videoCaptureError=$script:videoCaptureError
        audioDevices=@($script:audioDevices)
        outputWav=$script:outputWav
        outputSessionFolder=$script:outputSessionFolder
        recordingStartedUtc=$script:recordingStartedUtc
        recordingError=$script:recordingError
        finalizationOk=$script:finalizationOk
        cameraDevices=@($script:cameraDevices)
        cameraModes=@($script:cameraModes)
        previewActive=[bool](
            ($null -ne $script:previewProcess -and -not $script:previewProcess.HasExited) -or
            ($null -ne $script:videoProcess -and -not $script:videoProcess.HasExited -and $script:videoRecording)
        )
        previewDevice=$script:previewDevice
        previewMode=$script:previewMode
        previewFrames=$(if ($null -ne $script:recordingStudioReader) { $script:recordingStudioReader.Frames } elseif ($null -ne $script:previewReader) { $script:previewReader.Frames } else { 0 })
        previewPublished=$(if ($null -ne $script:recordingStudioReader) { $script:recordingStudioReader.PublishedFrames } elseif ($null -ne $script:previewReader) { $script:previewReader.PublishedFrames } else { 0 })
        previewWriteFailures=$(if ($null -ne $script:recordingStudioReader) { $script:recordingStudioReader.WriteFailures } elseif ($null -ne $script:previewReader) { $script:previewReader.WriteFailures } else { 0 })
        previewError=$script:previewError
    }
    $json = ConvertTo-Json -InputObject $payload -Depth 3 -Compress
    $temp = Join-Path $BridgeDir ('state.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $dest = Join-Path $BridgeDir 'state.json'
    [System.IO.File]::WriteAllText($temp,$json,[System.Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $dest) {
        $backup = Join-Path $BridgeDir 'state.backup'
        [System.IO.File]::Replace($temp,$dest,$backup)
        Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
    } else { [System.IO.File]::Move($temp,$dest) }
}

try {
    if (-not (Test-Path -LiteralPath $BridgeDir -PathType Container)) {
        throw 'Bridge directory does not exist.'
    }
    Publish-State  # Expose INITIALIZING while C# compiles.
    $required = @('Engine\NovaNative.ps1','Engine\NovaEngine.ps1',
                  'Engine\NovaSession.ps1','Engine\NovaVideo.ps1','Engine\NovaController.ps1')
    foreach ($part in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $EngineRoot $part) -PathType Leaf)) {
            throw "Missing engine module: $part"
        }
    }

    # Mirror application prerequisites without importing its UI or creating Recordings.
    # Type compilation uses System.Drawing and Windows.Forms, as required by the
    # existing native module; no controls, preview streams, or capture devices open.
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    . (Join-Path $PSScriptRoot 'Load-NovaMeterNative.ps1') -EngineRoot $EngineRoot
    if (-not ('NovaWaveRecorder' -as [type])) {
        throw 'Native NovaWaveRecorder type was not compiled.'
    }
    $script:recorder = New-Object NovaWaveRecorder
    if ($null -eq $script:recorder) { throw 'Recorder initialization returned null.' }
    $script:recorderCreated = $true

    # The helper/controller modules only declare functions at import time.
    # Source them in the same process and scope as the native recorder instance.
    $scriptDirectory = $EngineRoot
    $recordingsDirectory = Join-Path $EngineRoot 'Recordings'  # Path only; no mkdir.
    $ffmpegPath = Join-Path $EngineRoot 'tools\ffmpeg\ffmpeg.exe'
    $script:ffmpegAvailable = Test-Path -LiteralPath $ffmpegPath -PathType Leaf
    $ffmpegAvailable = $script:ffmpegAvailable
    $script:recording = $false
    $script:recordingStart = $null
    $script:currentFile = $null
    $script:currentVideoFile = $null
    $script:videoProcess = $null
    $script:videoRecording = $false
    $script:previewReader = $null
    $script:recordingPreviewReader = $null
    $script:previewRunning = $false
    $script:recordingStarting = $false
    $script:recordingStopping = $false

    foreach ($part in @('Engine\NovaEngine.ps1','Engine\NovaSession.ps1',
                        'Engine\NovaVideo.ps1','Engine\NovaController.ps1')) {
        . (Join-Path $EngineRoot $part)
    }
    foreach ($name in @('Get-NewRecordingPath','Write-NovaSessionMetadata',
                        'New-NovaCombinedMp4','Start-NovaVideoCapture',
                        'Stop-NovaVideoCapture','Start-NovaRecording','Stop-NovaRecording')) {
        if (-not (Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)) {
            throw "Engine function unavailable: $name"
        }
    }
    . (Join-Path $PSScriptRoot 'StudioPreviewReader.ps1')
    $dependenciesLoaded = $true
    # Retain NovaAudioDevice objects for the production controller and metadata.
    $script:audioDevices = @([NovaWaveRecorder]::GetDevices())
    if ($script:recorder.IsRecording -or $script:recorder.IsPreviewing -or
        $script:recording -or $script:videoRecording) {
        throw 'Recorder unexpectedly active after initialization.'
    }
    if ($script:ffmpegAvailable) {
        # FFmpeg writes normal DirectShow enumeration to stderr. Under
        # Windows PowerShell 5.1, merged native stderr can be promoted
        # to a terminating error when ErrorActionPreference is Stop.
        # Match the already-validated Probe-NovaEngine.ps1 behavior.
        $savedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $script:cameraDevices = @(Get-NovaVideoDevices)
            $script:previewError = ''
        } catch {
            $script:previewError = 'Camera inventory: ' + $_.Exception.Message
        } finally {
            $ErrorActionPreference = $savedPreference
        }
    }
    $engineInitialized = $true
    $ok = $true
    $state = 'READY'
} catch {
    $errorMessage = $_.Exception.ToString()
    $state = 'ERROR'
}
try { Publish-State } catch { Write-Error "Could not publish engine readiness: $($_.Exception.Message)"; exit 2 }
if (-not $ok) {
    if ($null -ne $script:recorder) { try { $script:recorder.Dispose() } catch {} }
    exit 1
}


# Worker owns exclusive preview camera process; independent of production capture functions.
# Preview-only output is reduced to 960px and 24fps; input camera mode is unchanged.
function Stop-StudioCameraPreview {
    $p = $script:previewProcess
    if ($null -ne $p -and -not $p.HasExited) {
        try { $p.Kill(); if (-not $p.WaitForExit(5000)) { throw 'Preview FFmpeg did not stop within 5 seconds.' } }
        catch { $script:previewError = 'Preview stop: ' + $_.Exception.Message; throw }
    }
    if ($null -ne $script:previewReader) { $script:previewReader.Dispose(); $script:previewReader = $null }
    if ($null -ne $p) { $p.Dispose() }
    $script:previewProcess = $null
    $script:previewDevice = ''
    $script:previewMode = ''
    if (Test-Path -LiteralPath $script:previewFramePath) { Remove-Item -LiteralPath $script:previewFramePath -Force -ErrorAction SilentlyContinue }
}
function Set-StudioCameraModes([object]$request) {
    if ($script:state -ne 'READY' -or $script:recorder.IsRecording -or $null -ne $script:previewProcess) { throw 'Camera mode discovery requires idle preview and recorder.' }
    $device = [string]$request.deviceName
    if ($device -notin @($script:cameraDevices)) { throw 'Selected camera was not enumerated.' }
    # Mode enumeration uses FFmpeg stderr too. Keep the same narrowly
    # scoped preference override and restore Stop for all other work.
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $script:cameraModes = @(Get-NovaVideoModes -DeviceName $device)
    } finally {
        $ErrorActionPreference = $savedPreference
    }
    if ($script:cameraModes.Count -eq 0) { throw 'No usable MJPEG modes discovered for this camera.' }
    $script:previewError = ''
}
function Start-StudioCameraPreview([object]$request, [bool]$InternalAvPreflight = $false) {
    # External START_PREVIEW is READY-only. The A/V controller may request its
    # own preview preflight after transitioning to STARTING, while audio remains idle.
    $allowedState = ($script:state -eq 'READY') -or
        ($InternalAvPreflight -and $script:state -eq 'STARTING')
    if (-not $allowedState -or $script:recorder.IsRecording -or
        $script:recording -or $script:videoRecording) {
        throw 'Camera preview requires no recording and an authorized controller state.'
    }
    if ($null -ne $script:previewProcess) { throw 'Camera preview already started.' }
    if (-not $script:ffmpegAvailable) { throw 'Portable FFmpeg is unavailable.' }
    $device = [string]$request.deviceName
    $key = [string]$request.modeKey
    if ($device -notin @($script:cameraDevices)) { throw 'Camera not in validated inventory.' }
    $modes = @($script:cameraModes | Where-Object { $_.Key -eq $key })
    if ($modes.Count -ne 1) { throw 'Select an enumerated camera mode.' }
    $mode = $modes[0]
    $size = '{0}x{1}' -f $mode.Width,$mode.Height
    $rate = [string]$mode.MaxFps
    $args = '-hide_banner -loglevel error -f dshow -rtbufsize 128M -video_size {0} -framerate {1} -vcodec mjpeg -i "video={2}" -an -vf "fps=24,scale=960:-2:flags=fast_bilinear" -f image2pipe -c:v mjpeg -q:v 5 pipe:1' -f $size,$rate,$device
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName=$ffmpegPath; $psi.Arguments=$args
    $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $psi.RedirectStandardInput=$false
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo=$psi
    try {
        if (-not $p.Start()) { throw 'Could not launch FFmpeg preview.' }
        $reader = New-Object NovaStudioPreviewReader -ArgumentList $p,$script:previewFramePath
        $reader.Start()
        $script:previewProcess = $p
        $script:previewReader = $reader
        $script:previewDevice = $device
        $script:previewMode = $key
        $script:previewError = ''
    } catch {
        try { if (-not $p.HasExited) { $p.Kill() } } catch {}
        try { $p.Dispose() } catch {}
        throw
    }
}

# I3B-I1-R1: Every A/V start must prove a usable camera preview frame,
# regardless of whether the operator opened the idle preview first.
# No session files are allocated until this preflight has succeeded.
function Prepare-StudioCameraForAv([string]$device, [string]$modeKey) {
    $script:cameraStartupStage = 'Checking camera preview readiness'
    # A running preview from a different camera/mode cannot authorize this capture.
    if ($null -ne $script:previewProcess -and
        ($script:previewProcess.HasExited -or $script:previewDevice -ne $device -or $script:previewMode -ne $modeKey)) {
        Stop-StudioCameraPreview
    }
    if ($null -eq $script:previewProcess) {
        $script:cameraStartupStage = 'Opening camera for automatic preflight'
        Start-StudioCameraPreview ([pscustomobject]@{deviceName=$device; modeKey=$modeKey}) $true
    }
    $script:cameraStartupStage = 'Waiting for first verified preview frame'
    $deadline = (Get-Date).AddSeconds(12)
    while ($null -eq $script:previewReader -or $script:previewReader.PublishedFrames -lt 1) {
        if ($null -eq $script:previewProcess -or $script:previewProcess.HasExited) {
            $reason = if ($null -ne $script:previewReader) { [string]$script:previewReader.Error } else { '' }
            throw ('Camera exited during preview preflight. ' + $reason)
        }
        if ((Get-Date) -ge $deadline) {
            $reason = [string]$script:previewReader.Error
            throw ('Camera preview preflight timed out after 12 seconds. ' + $reason)
        }
        Publish-State
        Start-Sleep -Milliseconds 100
    }
    $script:cameraStartupStage = 'First preview frame verified; releasing camera'
    Stop-StudioCameraPreview
    if ($null -ne $script:previewProcess) { throw 'Camera preview did not release.' }
}

# WP-02B2B-I3B-I1: Studio-only A/V start adapter.
# Model the production camera ownership, readiness gate and FFmpeg dual-output
# path without editing the production engine or its WinForms PictureBox reader.
# Stop and mux still use the production Stop-NovaRecording controller.
function Stop-StudioRecordingReader {
    if ($null -ne $script:recordingStudioReader) {
        try { $script:recordingStudioReader.Dispose() } finally { $script:recordingStudioReader = $null }
    }
}
function Start-StudioVideoCapture([string]$device, [object]$mode, [string]$output) {
    if ($script:videoRecording -or $null -ne $script:videoProcess) { throw 'Video capture is already active.' }
    if (-not $script:ffmpegAvailable) { throw 'Portable FFmpeg is missing.' }
    $size = '{0}x{1}' -f [int]$mode.Width,[int]$mode.Height
    # Preserve the production pipeline: native MJPEG stream-copy to AVI and
    # a second continuously drained MJPEG stdout preview. No live transcoding.
    $args = @(
        '-hide_banner', '-loglevel', 'warning', '-f', 'dshow',
        '-rtbufsize', '256M', '-video_size', $size,
        '-framerate', ([string]$mode.MaxFps), '-vcodec', ([string]$mode.Codec),
        '-i', ('video="' + $device + '"'),
        '-progress', 'pipe:2', '-stats_period', '0.05', '-nostats', '-y',
        '-map', '0:v:0', '-c:v', 'copy', '-f', 'avi', ('"' + $output + '"'),
        '-map', '0:v:0', '-c:v', 'copy', '-f', 'image2pipe', 'pipe:1'
    ) -join ' '
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ffmpegPath; $psi.Arguments = $args
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    try {
        if (-not $process.Start()) { throw 'Could not launch recording FFmpeg.' }
        # NovaFfmpegReadyMonitor exclusively drains stderr and recognizes
        # progress frame >= 1. Studio reader exclusively drains stdout.
        $script:videoReadyMonitor = New-Object NovaFfmpegReadyMonitor -ArgumentList $process
        $script:videoReadyMonitor.Start()
        $script:recordingStudioReader = New-Object NovaStudioPreviewReader -ArgumentList $process,$script:previewFramePath
        # The StudioPreviewReader normally drains stderr. During recording the
        # production readiness monitor owns it, so start stdout *only*.
        $script:recordingStudioReader.StartWithoutStderr()
        $script:videoProcess = $process
        $script:videoRecording = $true
        Start-Sleep -Milliseconds 350
        if ($process.HasExited) { throw ('FFmpeg video recording exited (code {0}).' -f $process.ExitCode) }
    } catch {
        $failure = $_
        if ($script:videoRecording) {
            try { Stop-NovaVideoCapture } catch {}
        } else {
            try { if (-not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(2000) } } catch {}
            try { $process.Dispose() } catch {}
            if ($null -ne $script:videoReadyMonitor) { try { $script:videoReadyMonitor.Dispose() } catch {}; $script:videoReadyMonitor=$null }
        }
        try { Stop-StudioRecordingReader } catch {}
        throw $failure
    }
}
function Start-NovaAvSession([object]$request) {
    if ($script:state -ne 'READY' -or $script:recording -or $script:recorder.IsRecording -or $script:videoRecording) {
        throw 'Recorder must be READY before A/V start.'
    }
    if (-not $script:ffmpegAvailable) { throw 'FFmpeg unavailable.' }
    $id = [int]$request.deviceId
    $selected = @($script:audioDevices | Where-Object { $_.Id -eq $id })
    if ($selected.Count -ne 1) { throw 'Selected microphone is unavailable.' }
    $gain = [double]$request.gainDb
    if ([double]::IsNaN($gain) -or $gain -lt 0 -or $gain -gt 18) { throw 'Gain outside 0 to +18 dB.' }
    $camera = [string]$request.deviceName
    $key = [string]$request.modeKey
    if ($camera -notin @($script:cameraDevices)) { throw 'Selected camera is not enumerated.' }
    $modes = @($script:cameraModes | Where-Object { $_.Key -eq $key })
    if ($modes.Count -ne 1) { throw 'Choose a valid MJPEG camera mode.' }
    $mode = $modes[0]
    Stop-StudioMicMonitor # Stop WinMM preview before video-readiness gate.
    $script:state = 'STARTING'
    $script:recordingError = ''
    $script:errorMessage = ''
    $script:videoCaptureError = ''
    $script:finalizationOk = $false
    $script:outputWav = ''; $script:outputAvi = ''; $script:outputMp4 = ''
    $script:outputSessionFolder = ''
    $script:videoReady = $false
    $script:cameraStartupStage = 'Preparing A/V camera'
    $script:activeSessionHasVideo = $true
    $script:activeAudioDevice = $selected[0]
    $script:activeGainDb = $gain
    $script:activeVideoDevice = $camera
    $script:activeVideoMode = $mode
    Publish-State
    try {
        # Explicit camera preflight makes both supported entry states equivalent:
        # idle camera or previously running matching preview. No user click order.
        Prepare-StudioCameraForAv $camera $key
        $script:cameraStartupStage = 'DirectShow handoff: waiting 3 seconds'
        Publish-State
        Start-Sleep -Milliseconds 3000
        # Allocate a session only after selection and camera preflight succeed.
        $script:currentFile = Get-NewRecordingPath
        $script:currentVideoFile = Get-VideoRecordingPath -AudioPath $script:currentFile
        $script:currentVideoMode = $mode
        $script:outputWav = [string]$script:currentFile
        $script:outputAvi = [string]$script:currentVideoFile
        $script:outputSessionFolder = Split-Path -Parent $script:currentFile
        $script:recorder.SetGainDb($gain)
        $script:cameraStartupStage = 'Starting full-resolution recording FFmpeg'
        Publish-State
        Start-StudioVideoCapture $camera $mode $script:currentVideoFile
        $script:cameraStartupStage = 'Waiting for first recording video frame'
        $deadline = (Get-Date).AddSeconds(15)
        while (-not $script:videoReadyMonitor.VideoReady) {
            if ($script:videoProcess.HasExited) { throw 'FFmpeg exited before first video frame.' }
            if ((Get-Date) -ge $deadline) { throw 'Video readiness timed out after 15 seconds.' }
            # Heartbeat while waiting: do not let Studio assume the worker died.
            Publish-State
            Start-Sleep -Milliseconds 100
        }
        $script:videoReady = $true
        # Audio begins only once the video frame readiness gate succeeds.
        $script:recorder.Start($script:activeAudioDevice.Id,$script:currentFile)
        $script:recording = $true
        $script:recordingStart = Get-Date
        $script:recordingStartedUtc = $script:recordingStart.ToUniversalTime().ToString('o')
        $script:cameraStartupStage = ''
        $script:state = 'RECORDING'
    } catch {
        $script:cameraStartupStage = 'Camera start failed'
        # A preflight failure must not leave an idle FFmpeg holding the webcam.
        if ($null -ne $script:previewProcess) { try { Stop-StudioCameraPreview } catch {} }
        $script:videoCaptureError = $_.Exception.ToString()
        $script:recordingError = $script:videoCaptureError
        $script:errorMessage = $script:recordingError
        # Preserve error while attempting atomic-start cleanup; never claim success.
        if ($script:videoRecording) { try { Stop-NovaVideoCapture } catch {} }
        try { Stop-StudioRecordingReader } catch {}
        if ($script:recorder.IsRecording) { try { $script:recorder.Stop() } catch {} }
        $script:recording = $false
        $script:state = 'ERROR'
        throw
    }
}
function Confirm-NovaWave([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Finalized WAV missing.' }
    $stream = [System.IO.File]::OpenRead($path)
    try {
        if ($stream.Length -le 44) { throw 'Finalized WAV is too small.' }
        $header = New-Object byte[] 12
        if ($stream.Read($header,0,12) -ne 12 -or
            [System.Text.Encoding]::ASCII.GetString($header,0,4) -ne 'RIFF' -or
            [System.Text.Encoding]::ASCII.GetString($header,8,4) -ne 'WAVE') {
            throw 'WAV RIFF/WAVE signature missing.'
        }
    } finally { $stream.Dispose() }
}
function Confirm-NovaAvResults([object]$result) {
    if ($result.AudioStopError) { throw ('Audio stop error: '+$result.AudioStopError) }
    if ($result.VideoStopError) { throw ('Video stop error: '+$result.VideoStopError) }
    Confirm-NovaWave $script:outputWav
    if (-not (Test-Path -LiteralPath $script:outputAvi -PathType Leaf)) { throw 'Finalized AVI missing.' }
    if ((Get-Item -LiteralPath $script:outputAvi).Length -le 4096) { throw 'Finalized AVI is suspiciously small.' }
    $metadata = Join-Path $result.SessionFolder 'session.json'
    if (-not (Test-Path -LiteralPath $metadata -PathType Leaf)) { throw 'Session metadata missing.' }
    if ([string]::IsNullOrWhiteSpace([string]$result.CombinedPath) -or
        -not (Test-Path -LiteralPath ([string]$result.CombinedPath) -PathType Leaf)) {
        throw 'Combined MP4 missing. Preserve WAV and AVI for inspection.'
    }
    $mp4 = Get-Item -LiteralPath ([string]$result.CombinedPath)
    if ($mp4.Length -le 4096) { throw 'Combined MP4 is suspiciously small.' }
    $script:outputMp4 = $mp4.FullName
}
function Stop-NovaAvSession {
    if ($script:state -ne 'RECORDING' -or -not $script:recording -or -not $script:activeSessionHasVideo) {
        throw 'No active A/V session available to stop.'
    }
    $script:state = 'STOPPING'
    Publish-State
    try {
        $script:state = 'FINALIZING'
        Publish-State
        # Production controller handles FFmpeg graceful q-stop, WAV stop,
        # metadata, and existing 300ms calibrated MP4 mux.
        try {
            $result = Stop-NovaRecording -AudioDevice $script:activeAudioDevice -GainDb $script:activeGainDb -VideoDevice $script:activeVideoDevice
        } finally {
            # Reader only drains stdout. If stop threw, still release its resources.
            try { Stop-StudioRecordingReader } catch {}
        }
        if ($script:videoCaptureError) { throw $script:videoCaptureError }
        Confirm-NovaAvResults $result
        $script:finalizationOk = $true
        $script:cameraStartupStage = ''
        $script:recordingError = ''
        $script:errorMessage = ''
        $script:recordingStartedUtc = ''
        $script:state = 'READY'
        Resume-StudioMicMonitor
    } catch {
        $script:recordingError = $_.Exception.ToString()
        $script:errorMessage = $script:recordingError
        $script:state = 'ERROR'
        throw
    }
}

# WP-02C-I2: One native WinMM microphone owner per worker. Preview never writes WAV.
function Stop-StudioMicMonitor {
    if ($script:recorder.IsPreviewing) { $script:recorder.StopPreview() }
}
function Start-StudioMicMonitor {
    if (-not $script:monitorEnabled -or $script:monitorDeviceId -lt 0) { return }
    if ($script:state -ne 'READY' -or $script:recorder.IsRecording -or $script:recording) { return }
    try {
        $script:recorder.SetGainDb($script:monitorGainDb)
        if (-not $script:recorder.IsPreviewing) {
            $script:recorder.StartPreview($script:monitorDeviceId)
        }
        $script:monitorError = ''
    } catch {
        $script:monitorError = 'Microphone monitor could not start: ' + $_.Exception.Message
        # Keep recording transport usable; a monitor failure isn't a recording failure.
        try { Stop-StudioMicMonitor } catch {}
    }
}
function Set-StudioMicMonitor([object]$request) {
    if ($script:state -ne 'READY' -or $script:recording -or $script:recorder.IsRecording) {
        throw 'Microphone monitor can only change while READY.'
    }
    Stop-StudioMicMonitor
    $script:monitorEnabled = [bool]$request.enabled
    $script:monitorDeviceId = -1
    $script:monitorError = ''
    if (-not $script:monitorEnabled) { return }
    $id = [int]$request.deviceId
    $devices = @($script:audioDevices | Where-Object { $_.Id -eq $id })
    if ($devices.Count -ne 1) {
        $script:monitorEnabled = $false
        $script:monitorError = 'Selected monitor microphone is unavailable.'
        return
    }
    $gain = [double]$request.gainDb
    if ([double]::IsNaN($gain) -or $gain -lt 0 -or $gain -gt 18) {
        $script:monitorEnabled = $false
        $script:monitorError = 'Monitor gain outside 0 to +18 dB.'
        return
    }
    $script:monitorDeviceId = $id
    $script:monitorGainDb = $gain
    Start-StudioMicMonitor
}
function Resume-StudioMicMonitor {
    # A failure to reopen the idle monitor must never fail a finalized WAV/MP4.
    if ($script:state -eq 'READY' -and $script:monitorEnabled) {
        Start-StudioMicMonitor
    }
}

# Real capture commands run only in the controller process. WPF never owns native buffers.
function Start-NovaAudioSession([object]$request) {
    if ($script:state -ne 'READY' -or $script:recorder.IsRecording -or $script:recording) {
        throw 'Recorder is not idle.'
    }
    $script:activeSessionHasVideo = $false
    $script:outputAvi = ''; $script:outputMp4 = ''
    $requestedId = [int]$request.deviceId
    $selected = @($script:audioDevices | Where-Object { $_.Id -eq $requestedId })
    if ($selected.Count -ne 1) { throw "Selected microphone ID $requestedId is unavailable." }
    $gain = [double]$request.gainDb
    if ([double]::IsNaN($gain) -or $gain -lt 0 -or $gain -gt 18) {
        throw 'Gain must be between 0 and +18 dB.'
    }
    Stop-StudioMicMonitor # Recording will exclusively own the same native recorder.
    $script:state = 'STARTING'
    $script:recordingError = ''
    $script:finalizationOk = $false
    $script:outputWav = ''
    $script:outputSessionFolder = ''
    $script:activeAudioDevice = $selected[0]
    $script:activeGainDb = $gain
    Publish-State
    try {
        # Reuse the verified production start controller without video or preview.
        Start-NovaRecording -AudioDevice $script:activeAudioDevice -GainDb $gain -VideoEnabled $false
        $script:recording = $true
        $script:recordingStart = Get-Date
        $script:recordingStartedUtc = $script:recordingStart.ToUniversalTime().ToString('o')
        $script:outputWav = [string]$script:currentFile
        $script:outputSessionFolder = Split-Path -Parent $script:currentFile
        $script:state = 'RECORDING'
    } catch {
        $script:recordingError = $_.Exception.ToString()
        $script:errorMessage = $script:recordingError
        $script:state = 'ERROR'
        throw
    }
}
function Stop-NovaAudioSession {
    if ($script:activeSessionHasVideo) { throw 'Active session is A/V: use STOP_AV.' }
    if ($script:state -ne 'RECORDING' -or -not $script:recording) {
        throw 'No active recording is available to stop.'
    }
    $script:state = 'STOPPING'
    Publish-State
    try {
        $script:state = 'FINALIZING'
        Publish-State
        $result = Stop-NovaRecording -AudioDevice $script:activeAudioDevice -GainDb $script:activeGainDb -VideoDevice $null
        if ($result.AudioStopError) { throw "Audio capture stop failed: $($result.AudioStopError)" }
        if ($result.VideoStopError) { throw "Unexpected video stop error: $($result.VideoStopError)" }
        $path = [string]$script:outputWav
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Finalized WAV is missing.' }
        $stream = [System.IO.File]::OpenRead($path)
        try {
            if ($stream.Length -le 44) { throw 'WAV validation failed: file is too small.' }
            $head = New-Object byte[] 12
            if ($stream.Read($head,0,12) -ne 12 -or
                [System.Text.Encoding]::ASCII.GetString($head,0,4) -ne 'RIFF' -or
                [System.Text.Encoding]::ASCII.GetString($head,8,4) -ne 'WAVE') {
                throw 'WAV validation failed: invalid RIFF/WAVE header.'
            }
        } finally { $stream.Dispose() }
        # Require the existing session metadata artifact, but do not rewrite it here.
        $metadataFile = Join-Path $result.SessionFolder 'session.json'
        if (-not (Test-Path -LiteralPath $metadataFile -PathType Leaf)) {
            throw 'Session metadata file is missing after finalization.'
        }
        $script:finalizationOk = $true
        $script:recordingError = ''
        $script:errorMessage = ''
        $script:recordingStartedUtc = ''
        $script:state = 'READY'
        Resume-StudioMicMonitor
    } catch {
        $script:recordingError = $_.Exception.ToString()
        $script:errorMessage = $script:recordingError
        $script:state = 'ERROR'
        throw
    }
}
function Recover-NovaActiveRecording {
    # Parent loss is never a reason to discard raw audio.
    if ($script:recording -and $script:recorder.IsRecording) {
        try {
            if ($script:activeSessionHasVideo) { Stop-NovaAvSession } else { Stop-NovaAudioSession }
        } catch {
            try { $script:recorder.Stop() } catch {}
            $script:state = 'ERROR'
            $script:recordingError = 'Emergency finalization failed: ' + $_.Exception.ToString()
        }
    } elseif ($script:recorder.IsRecording) {
        try { $script:recorder.Stop() } catch { $script:recordingError = $_.Exception.ToString(); $script:state='ERROR' }
    }
    if ($script:videoRecording) {
        try { Stop-NovaVideoCapture } catch { $script:videoCaptureError = $_.Exception.ToString(); $script:state='ERROR' }
    }
    try { Stop-StudioRecordingReader } catch {}
    try { Publish-State } catch {}
}

try {
    while ($true) {
        # 10 Hz status/meter publication; capture callback and UI remain separate.
        Start-Sleep -Milliseconds 100
        if (-not (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)) {
            Recover-NovaActiveRecording
            break
        }
        $requestPath = Join-Path $BridgeDir 'request.json'
        $disconnectRequested = $false
        if (Test-Path -LiteralPath $requestPath) {
            try {
                $request = [System.IO.File]::ReadAllText($requestPath,[System.Text.Encoding]::UTF8) | ConvertFrom-Json
                Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
                $lastRequestSequence = [int]$request.sequence
                $command = [string]$request.command
                switch ($command) {
                    'GET_VIDEO_MODES' { $lastCommand='GET_VIDEO_MODES'; Set-StudioCameraModes $request }
                    'START_PREVIEW' { $lastCommand='START_PREVIEW'; Start-StudioCameraPreview $request }
                    'STOP_PREVIEW' { $lastCommand='STOP_PREVIEW'; Stop-StudioCameraPreview }
                    'PING' { $lastCommand = 'PONG' }
                    'SET_MONITOR' {
                        $lastCommand = 'SET_MONITOR'
                        try { Set-StudioMicMonitor $request } catch { $script:monitorError = $_.Exception.Message }
                    }
                    'START_AUDIO' {
                        $lastCommand = 'START_AUDIO'
                        Start-NovaAudioSession $request
                    }
                    'STOP_AUDIO' {
                        $lastCommand = 'STOP_AUDIO'
                        Stop-NovaAudioSession
                    }
                    'START_AV' {
                        $lastCommand = 'START_AV'
                        Start-NovaAvSession $request
                    }
                    'STOP_AV' {
                        $lastCommand = 'STOP_AV'
                        Stop-NovaAvSession
                    }
                    'DISCONNECT' {
                        if ($null -ne $script:previewProcess -or $script:videoRecording -or $script:recorder.IsRecording -or $script:recording -or
                            $state -in @('STARTING','STOPPING','FINALIZING')) {
                            $lastCommand = 'REJECTED: ACTIVE RECORDING'
                        } else {
                            $lastCommand = 'DISCONNECT'
                            $disconnectRequested = $true
                        }
                    }
                    default { $lastCommand = 'REJECTED: UNKNOWN COMMAND' }
                }
            } catch {
                $lastCommand = 'COMMAND FAILED'
                if (-not $script:recordingError) { $script:recordingError = $_.Exception.ToString() }
                $errorMessage = $script:recordingError
                if ($command -in @('GET_VIDEO_MODES','START_PREVIEW','STOP_PREVIEW')) {
                    $script:previewError = $_.Exception.ToString()
                } elseif (-not $script:recorder.IsRecording -and $state -notin @('RECORDING','STOPPING','FINALIZING')) {
                    $state = 'ERROR'
                }
            }
        }
        if ($null -ne $script:videoProcess -and $script:videoRecording -and $script:videoProcess.HasExited -and $script:state -eq 'RECORDING') {
            # Keep STOP_AV available for finalizing any still-active WAV.
            # Do not transition to ERROR until STOP has attempted finalization.
            $script:videoCaptureError = 'Recording FFmpeg exited unexpectedly; STOP A/V to preserve raw files.'
            $script:recordingError = $script:videoCaptureError
            $script:errorMessage = $script:recordingError
        }
        if ($null -ne $script:previewProcess -and $script:previewProcess.HasExited) {
            $script:previewError = 'FFmpeg preview exited unexpectedly. ' + $(if ($script:previewReader) { $script:previewReader.Error } else { '' })
            try { Stop-StudioCameraPreview } catch {}
        }
        try { Publish-State } catch { $errorMessage = $_.Exception.ToString(); break }
        if ($disconnectRequested) { break }
    }
} finally {
    try { Stop-StudioCameraPreview } catch {}
    try { Stop-StudioMicMonitor } catch {}
    Recover-NovaActiveRecording
    if ($null -ne $script:recorder) {
        # Dispose only after attempting an orderly finalization.
        try { $script:recorder.Dispose() } catch {}
    }
}
