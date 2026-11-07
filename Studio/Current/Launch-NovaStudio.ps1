# NOVA Studio WP-02B2B-I3B-I1-R1 | Real synchronized A/V candidate
# Child worker owns WAV capture; UI graphics remain simulated.
# Run with Windows PowerShell 5.1 in STA mode.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'This prototype requires Windows PowerShell 5.1 and Windows WPF.'
}
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    throw 'Run with powershell.exe -NoProfile -STA -File .\Launch-NovaStudio.ps1'
}
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$xamlPath = Join-Path $PSScriptRoot 'UI\NovaStudio.xaml'
if (-not (Test-Path -LiteralPath $xamlPath)) { throw "Missing XAML: $xamlPath" }
# Explicit UTF-8 decoding fixes the mojibake observed in WP-02A on Windows PowerShell 5.1.
$xamlText = [System.IO.File]::ReadAllText($xamlPath, [System.Text.Encoding]::UTF8)
[xml]$layout = $xamlText
$reader = New-Object System.Xml.XmlNodeReader($layout)
try {
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
} finally { $reader.Close() }

$names = @(
    'CaptureTab', 'AudioTab', 'VideoTab', 'SessionsTab', 'SettingsButton',
    'CaptureWorkspace', 'AudioWorkspace', 'VideoWorkspace', 'SessionsWorkspace', 'SettingsWorkspace',
    'WorkspaceTitle', 'WorkspaceHint', 'HeadButton', 'LargeHeadButton', 'CompactHeadOutline',
    'LargeHeadOutline', 'CompactMouth', 'LargeMouth', 'CompactGlow', 'LargeGlow',
    'LevelBars', 'WaveformLine', 'PeakReadout', 'ClipReadout', 'GainSlider', 'GainValue',
    'ElapsedText', 'TransportStatus', 'TransportDot', 'RecordButton', 'StopButton', 'FooterStatus',
    'SpectrumBars', 'LabWaveform', 'JawGlow', 'EyesGlow', 'HaloGlow', 'HeadSignalStatus', 'RmsPeakReadout',
    'EngineStatus', 'MicInventory', 'CameraInventory', 'ScanEngineButton', 'ProbeStatus',
    'ConnectBridgeButton', 'DisconnectBridgeButton', 'PingBridgeButton', 'BridgeStatus', 'MicrophoneSelector',
    'CaptureVideoCheckBox', 'LiveCameraImage', 'CameraSelector', 'CameraModeSelector', 'StartPreviewButton', 'StopPreviewButton', 'CameraPreviewStatus', 'PreviewMetrics', 'VideoMonitorStatus'
)
$ui = @{}
foreach ($name in $names) {
    $element = $window.FindName($name)
    if ($null -eq $element) { throw "XAML missing required element: $name" }
    $ui[$name] = $element
}

function New-Brush([string]$hex) {
    $brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($hex)
    $brush.Freeze()
    return $brush
}
$brushes = @{
    active = New-Brush '#493567'
    inactive = New-Brush '#252C3C'
    low = New-Brush '#42C7A3'
    mid = New-Brush '#E6BB66'
    high = New-Brush '#E56F83'
    healthy = New-Brush '#94E2C3'
    warning = New-Brush '#E8C477'
    danger = New-Brush '#FF697E'
    head = New-Brush '#8266BE'
    headLoud = New-Brush '#AF75DB'
    headClip = New-Brush '#D34C72'
}

$script:studioMode = 'Capture'
$script:demoRecording = $false
$script:demoStart = [DateTime]::UtcNow
$script:tickCount = 0
$script:generator = [Random]::new()
$script:clipHold = 0
$script:peakHold = -48.0
$script:demoTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:demoTimer.Interval = [TimeSpan]::FromMilliseconds(85)

$tabMap = @{
    Capture = @('CaptureTab', 'CaptureWorkspace', 'CAPTURE WORKSPACE')
    Audio = @('AudioTab', 'AudioWorkspace', 'NOVA AUDIO LAB')
    Video = @('VideoTab', 'VideoWorkspace', 'VIDEO WORKSPACE')
    Sessions = @('SessionsTab', 'SessionsWorkspace', 'SESSION BROWSER')
    Settings = @('SettingsButton', 'SettingsWorkspace', 'SETTINGS')
}
function Set-Workspace([string]$name) {
    $script:studioMode = $name
    foreach ($key in @($tabMap.Keys)) {
        $target = $tabMap[$key]
        $ui[$target[0]].Background = if ($key -eq $name) { $brushes.active } else { $brushes.inactive }
        $ui[$target[1]].Visibility = if ($key -eq $name) {
            [System.Windows.Visibility]::Visible
        } else { [System.Windows.Visibility]::Collapsed }
    }
    $ui.WorkspaceTitle.Text = $tabMap[$name][2]
    $ui.WorkspaceHint.Text = if ($name -eq 'Audio') { 'SIGNAL ANATOMY / DEMO SPECTRUM' } elseif ($name -eq 'Capture') { 'AUDIO WAV OR A/V MP4 · EXPLICIT VIDEO OPT-IN' } else { 'DEMO WORKSPACE' }
}

$ui.CaptureTab.Add_Click({ Set-Workspace 'Capture' })
$ui.AudioTab.Add_Click({ Set-Workspace 'Audio' })
$ui.VideoTab.Add_Click({ Set-Workspace 'Video' })
$ui.SessionsTab.Add_Click({ Set-Workspace 'Sessions' })
$ui.SettingsButton.Add_Click({ Set-Workspace 'Settings' })
$ui.HeadButton.Add_Click({
    if ($script:studioMode -eq 'Audio') { Set-Workspace 'Capture' }
    else { Set-Workspace 'Audio' }
})
$ui.LargeHeadButton.Add_Click({ Set-Workspace 'Capture' })
# WP-02B1: Read-only engine discovery happens in an isolated child process.
# The child never starts the recorder, opens the camera, or creates a recording session.
$script:probeProcess = $null
$script:probeFile = $null
$script:probeStartedUtc = [DateTime]::MinValue
$script:probeTimeoutSeconds = 35
$script:probeHost = Join-Path $PSScriptRoot 'Bridge\Probe-NovaEngine.ps1'
$script:engineRoot = $null
$script:bridgeProcess = $null
$script:bridgeDir = $null
$script:bridgeState = 'OFFLINE'
$script:bridgeLastHeartbeat = [DateTime]::MinValue
$script:bridgeLastSequence = 0
$script:bridgePingSeq = 0
$script:bridgeLastPing = 0
$script:bridgeConnectUtc = [DateTime]::MinValue
$script:bridgePollTicks = 0
$script:bridgeHost = Join-Path $PSScriptRoot 'Bridge\Start-NovaControllerHost.ps1'
$script:pendingCaptureCommand = ''
$script:pendingCaptureSequence = 0
$script:pendingCaptureUtc = [DateTime]::MinValue
$script:realRecordingStartedUtc = [DateTime]::MinValue
$script:workerAudioActive = $false
$script:workerVideoActive = $false
$script:sessionHasVideo = $false
$script:workerState = 'OFFLINE'
$script:lastSessionPath = ''
$script:bridgeCommandError = ''
$script:cameraModesFor = ''
$script:previewActive = $false
$script:previewFramesSeen = 0
$script:previewLastFrameWrite = [DateTime]::MinValue
$script:previewRequest = ''
$script:previewSequence = 0
$script:previewImagePath = ''
$script:previewLastSeenTick = 0
$script:previewDisplayed = 0
$script:previewLastMetricsUtc = [DateTime]::UtcNow
$script:previewMetricsBaseline = @{ captured=0L; published=0L; displayed=0L }
$script:previewLatestState = $null
$script:previewRenderErrors = 0
$script:previewRenderTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:previewRenderTimer.Interval = [TimeSpan]::FromMilliseconds(40)
$script:cameraInventoryLoaded = $false
$ui.CameraSelector.DisplayMemberPath = ''
$ui.CameraModeSelector.DisplayMemberPath = 'Display'

$ui.GainSlider.Maximum = 18
$ui.GainValue.Text = '+16 dB · APPLIED ON RECORD'
$ui.MicrophoneSelector.DisplayMemberPath = 'Name'
$ui.MicrophoneSelector.SelectedValuePath = 'Id'



function Complete-NovaEngineProbe {
    if ($null -eq $script:probeProcess) { return }
    $process = $script:probeProcess
    $done = $process.HasExited
    $timedOut = (([DateTime]::UtcNow - $script:probeStartedUtc).TotalSeconds -ge $script:probeTimeoutSeconds)
    if (-not $done -and -not $timedOut) { return }
    if ($timedOut -and -not $done) { try { $process.Kill() } catch {} }
    $ui.ScanEngineButton.IsEnabled = $true
    try {
        if ($timedOut) { throw 'Discovery exceeded the 35-second timeout.' }
        if (-not (Test-Path -LiteralPath $script:probeFile)) { throw 'Discovery returned no result file.' }
        $json = [System.IO.File]::ReadAllText($script:probeFile, [System.Text.Encoding]::UTF8)
        $result = $json | ConvertFrom-Json
        if (-not $result.ok) { throw [string]$result.error }
        $micNames = @($result.microphones)
        $camNames = @($result.cameras)
        $ui.MicInventory.Text = if ($micNames.Count) { [string]$micNames[0] } else { 'No microphone detected' }
        $ui.CameraInventory.Text = if ($camNames.Count) { [string]$camNames[0] } else { 'No camera detected' }
        $ui.MicInventory.ToolTip = ($micNames -join [Environment]::NewLine)
        $ui.CameraInventory.ToolTip = ($camNames -join [Environment]::NewLine)
        $script:engineRoot = $result.engineRoot
        $ui.ConnectBridgeButton.IsEnabled = $true
        $ui.EngineStatus.Text = '● ENGINE FILES VERIFIED'
        $ui.EngineStatus.Foreground = $brushes.healthy
        $ui.ProbeStatus.Text = ('{0} mic(s) / {1} camera(s) · FFmpeg {2}' -f $micNames.Count, $camNames.Count, $(if($result.ffmpeg){'found'}else{'missing'}))
        $ui.FooterStatus.Text = 'REAL DEVICE INVENTORY LOADED · CONNECT TO ENABLE AUDIO'
    } catch {
        $script:engineRoot = $null
        $ui.ConnectBridgeButton.IsEnabled = $false
        $ui.EngineStatus.Text = '● ENGINE SCAN FAILED'
        $ui.EngineStatus.Foreground = $brushes.danger
        $ui.ProbeStatus.Text = [string]$_.Exception.Message
        $ui.FooterStatus.Text = 'ENGINE DISCOVERY FAILED · NO CAPTURE ATTEMPTED'
    } finally {
        try { if ($null -ne $process) { $process.Dispose() } } catch {}
        if ($script:probeFile -and (Test-Path -LiteralPath $script:probeFile)) {
            Remove-Item -LiteralPath $script:probeFile -Force -ErrorAction SilentlyContinue
        }
        $script:probeProcess = $null
        $script:probeFile = $null
    }
}

$ui.ScanEngineButton.Add_Click({
    if ($null -ne $script:probeProcess -or $null -ne $script:bridgeProcess) { return }
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Choose your NOVA_Recorder repository root (contains Engine and Tools)'
    $dialog.ShowNewFolderButton = $false
    try {
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $root = $dialog.SelectedPath
    } finally { $dialog.Dispose() }
    $script:probeFile = Join-Path ([System.IO.Path]::GetTempPath()) ('nova_probe_' + [Guid]::NewGuid().ToString('N') + '.json')
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Join-Path $PSHOME 'powershell.exe')
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -EngineRoot "{1}" -OutputJson "{2}"' -f $script:probeHost, $root, $script:probeFile
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    try {
        $script:probeProcess = [System.Diagnostics.Process]::Start($psi)
        if ($null -eq $script:probeProcess) { throw 'Could not start discovery subprocess.' }
        $script:probeStartedUtc = [DateTime]::UtcNow
        $ui.ScanEngineButton.IsEnabled = $false
        $ui.ProbeStatus.Text = 'Scanning devices (read-only)...'
        $ui.EngineStatus.Text = '● SCANNING ENGINE'
    } catch {
        $ui.ScanEngineButton.IsEnabled = $true
        $ui.ProbeStatus.Text = [string]$_.Exception.Message
        $script:probeProcess = $null
    }
})

# WP-02B2A: Persistent, capture-disabled controller-definition host.
# IPC is a per-launch private temp directory. Only PING and DISCONNECT are permitted.
function Write-NovaBridgeRequest([string]$type, [hashtable]$parameters=@{}) {
    if ($null -eq $script:bridgeProcess -or -not $script:bridgeDir -or $script:bridgeProcess.HasExited) {
        throw 'Controller worker is not running.'
    }
    $dest = Join-Path $script:bridgeDir 'request.json'
    if (Test-Path -LiteralPath $dest) { throw 'An IPC request is still pending.' }
    $script:bridgePingSeq++
    $request = @{ command=$type; sequence=$script:bridgePingSeq }
    foreach ($key in $parameters.Keys) { $request[$key] = $parameters[$key] }
    $json = $request | ConvertTo-Json -Compress
    $temp = Join-Path $script:bridgeDir ('request.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    [System.IO.File]::WriteAllText($temp,$json,[System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::Move($temp,$dest)
    return $script:bridgePingSeq
}
function Stop-NovaBridge {
    if ($null -eq $script:bridgeProcess) { return }
    # No force kill is permitted unless the last heartbeat proves idle.
    if ($script:previewActive -or $script:previewRequest -or $script:workerVideoActive -or
        $script:workerAudioActive -or $script:workerState -in @('STARTING','RECORDING','STOPPING','FINALIZING') -or $script:pendingCaptureCommand) {
        throw 'Cannot disconnect: recording is active or command completion is unconfirmed.'
    }
    $process = $script:bridgeProcess
    if (-not $process.HasExited) {
        [void](Write-NovaBridgeRequest 'DISCONNECT')
        if (-not $process.WaitForExit(3500)) {
            throw 'Worker did not acknowledge disconnect. It was NOT terminated. Inspect state before retrying.'
        }
    }
    try { $process.Dispose() } catch {}
    $script:bridgeProcess = $null
    if ($script:bridgeDir -and (Test-Path -LiteralPath $script:bridgeDir)) {
        Remove-Item -LiteralPath $script:bridgeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $script:bridgeDir = $null
    $script:bridgeState = 'OFFLINE'
    $script:workerState = 'OFFLINE'
    $script:workerAudioActive = $false
    $ui.BridgeStatus.Text = 'Bridge offline'
    $ui.DisconnectBridgeButton.IsEnabled = $false
    $ui.PingBridgeButton.IsEnabled = $false
    $ui.ConnectBridgeButton.IsEnabled = ($null -ne $script:engineRoot)
    $ui.MicrophoneSelector.IsEnabled = $false
    $script:previewActive = $false
    $script:previewRequest = ''
    $script:cameraInventoryLoaded = $false
    $script:workerVideoActive = $false
    $script:sessionHasVideo = $false
    $ui.CameraSelector.Items.Clear()
    $ui.CameraModeSelector.Items.Clear()
    $ui.CaptureVideoCheckBox.IsChecked = $false
    $ui.CaptureVideoCheckBox.IsEnabled = $false
    $ui.CameraSelector.IsEnabled = $false
    $ui.CameraModeSelector.IsEnabled = $false
    $ui.StartPreviewButton.IsEnabled = $false
    $ui.StopPreviewButton.IsEnabled = $false
    $ui.LiveCameraImage.Source = $null
    $ui.LiveCameraImage.Visibility = [System.Windows.Visibility]::Collapsed
    $ui.CameraPreviewStatus.Text = 'Preview disconnected'
    $ui.RecordButton.IsEnabled = $false
    $ui.StopButton.IsEnabled = $false
    $ui.EngineStatus.Text = '● ENGINE FILES VERIFIED'
}
function Update-NovaRecordingTransport([string]$state) {
    switch ($state) {
        'READY' {
            $avRequested = ($ui.CaptureVideoCheckBox.IsChecked -eq $true)
            $hasAvSelection = ($null -ne $ui.CameraSelector.SelectedItem -and $null -ne $ui.CameraModeSelector.SelectedItem)
            $ui.RecordButton.IsEnabled = (-not $script:pendingCaptureCommand -and -not $script:previewRequest -and $null -ne $ui.MicrophoneSelector.SelectedItem -and
                $(if ($avRequested) { $hasAvSelection } else { -not $script:previewActive }))
            $ui.CaptureVideoCheckBox.IsEnabled = (-not $script:pendingCaptureCommand)
            $ui.RecordButton.Content = $(if ($avRequested) { '● RECORD A/V' } else { '● RECORD WAV' })
            $ui.StopButton.IsEnabled = $false
            $ui.MicrophoneSelector.IsEnabled = (-not $script:pendingCaptureCommand)
            $ui.GainSlider.IsEnabled = $true
            $ui.TransportStatus.Text = '● AUDIO READY'
            $ui.TransportStatus.Foreground = $brushes.healthy
            $ui.TransportDot.Fill = $brushes.healthy
        }
        'RECORDING' {
            $ui.RecordButton.IsEnabled = $false
            $ui.StopButton.IsEnabled = (-not $script:pendingCaptureCommand)
            $ui.MicrophoneSelector.IsEnabled = $false
            $ui.CaptureVideoCheckBox.IsEnabled = $false
            $ui.GainSlider.IsEnabled = $false
            $ui.TransportStatus.Text = $(if ($script:sessionHasVideo) { '● RECORDING A/V' } else { '● RECORDING WAV' })
            $ui.TransportStatus.Foreground = $brushes.danger
            $ui.TransportDot.Fill = $brushes.danger
        }
        default {
            $ui.RecordButton.IsEnabled = $false
            $ui.StopButton.IsEnabled = $false
            $ui.MicrophoneSelector.IsEnabled = $false
            $ui.CaptureVideoCheckBox.IsEnabled = $false
            $ui.TransportStatus.Text = '● ' + $state
            $ui.TransportStatus.Foreground = $brushes.warning
            $ui.TransportDot.Fill = $brushes.warning
        }
    }
}
function Update-NovaBridge {
    if ($null -eq $script:bridgeProcess) { return }
    if ($script:bridgeProcess.HasExited) {
        $message = 'Controller worker exited.'
        $lastFile = Join-Path $script:bridgeDir 'state.json'
        if (Test-Path -LiteralPath $lastFile) {
            try {
                $lastState = [System.IO.File]::ReadAllText($lastFile,[System.Text.Encoding]::UTF8) | ConvertFrom-Json
                if ($lastState.recordingError) { $message = [string]$lastState.recordingError }
                elseif ($lastState.error) { $message = [string]$lastState.error }
                else { $message = 'Worker exited after state: ' + [string]$lastState.state }
                if ($lastState.outputSessionFolder) { $message += ' · Session: ' + [string]$lastState.outputSessionFolder }
            } catch { $message += ' (unreadable state file)' }
        }
        $ui.ProbeStatus.Text = $message
        $ui.BridgeStatus.Text = 'WORKER EXITED · INSPECT SESSION'
        $ui.BridgeStatus.Foreground = $brushes.danger
        $ui.RecordButton.IsEnabled = $false
        $ui.StopButton.IsEnabled = $false
        $ui.DisconnectBridgeButton.IsEnabled = $false
        $ui.PingBridgeButton.IsEnabled = $false
        $script:workerState = 'ERROR'
        $script:pendingCaptureCommand = ''
        return
    }
    $stateFile = Join-Path $script:bridgeDir 'state.json'
    if (Test-Path -LiteralPath $stateFile) {
        try {
            $json = [System.IO.File]::ReadAllText($stateFile,[System.Text.Encoding]::UTF8)
            $state = $json | ConvertFrom-Json
            if ([int]$state.sequence -lt $script:bridgeLastSequence) { return }
            $script:bridgeLastSequence = [int]$state.sequence
            $script:bridgeLastHeartbeat = [datetime]::Parse([string]$state.utc).ToUniversalTime()
            $script:workerState = [string]$state.state
            $script:workerAudioActive = [bool]$state.audioCaptureStarted
            $script:workerVideoActive = [bool]$state.videoCaptureStarted
            $script:sessionHasVideo = [bool]$state.activeSessionHasVideo
            if ($script:workerState -eq 'INITIALIZING') {
                $ui.BridgeStatus.Text = 'Compiling native engine...'
                $ui.EngineStatus.Text = '● ENGINE INITIALIZING · CAPTURE DISABLED'
                return
            }
            if (-not $state.engineInitialized -or -not $state.recorderCreated -or -not $state.dependenciesLoaded) {
                throw 'Worker did not complete native initialization.'
            }
            if ($script:workerState -eq 'READY' -and $ui.MicrophoneSelector.Items.Count -eq 0) {
                foreach ($device in @($state.audioDevices)) { [void]$ui.MicrophoneSelector.Items.Add($device) }
                $ui.MicInventory.Text = '{0} native microphone(s) · select one above' -f $ui.MicrophoneSelector.Items.Count
                $ui.RecordButton.Content = '● RECORD WAV'
                $ui.StopButton.Content = '■ STOP WAV'
            }
            if (-not $script:cameraInventoryLoaded) {
                $script:cameraInventoryLoaded = $true
                foreach ($cam in @($state.cameraDevices)) { [void]$ui.CameraSelector.Items.Add([string]$cam) }
                $ui.CameraSelector.IsEnabled = ($ui.CameraSelector.Items.Count -gt 0)
                $ui.CameraPreviewStatus.Text = ('{0} camera(s) available · choose one to inspect modes' -f $ui.CameraSelector.Items.Count)
            }
            $script:previewActive = [bool]$state.previewActive
            $script:previewLatestState = $state
            $ui.VideoMonitorStatus.Text = if ($script:workerVideoActive) { '● RECORDING · LIVE CAMERA' } elseif ($script:previewActive) { 'LIVE CAMERA · 24 FPS TARGET' } else { 'NO CAMERA CONNECTED' }
            if ($script:previewRequest -and [int]$state.lastRequestSequence -eq $script:previewSequence) {
                $completedPreview = $script:previewRequest
                $script:previewRequest = ''
                if ([string]$state.lastCommand -eq 'COMMAND FAILED') {
                    $ui.CameraPreviewStatus.Text = 'Preview command failed: ' + [string]$state.previewError
                } elseif ($completedPreview -eq 'GET_VIDEO_MODES') {
                    $ui.CameraModeSelector.Items.Clear()
                    foreach ($mode in @($state.cameraModes)) { [void]$ui.CameraModeSelector.Items.Add($mode) }
                    $ui.CameraModeSelector.IsEnabled = ($ui.CameraModeSelector.Items.Count -gt 0)
                    $ui.CameraPreviewStatus.Text = ('{0} MJPEG mode(s) detected · select a mode' -f $ui.CameraModeSelector.Items.Count)
                } elseif ($completedPreview -eq 'START_PREVIEW') {
                    $ui.CameraPreviewStatus.Text = 'Camera starting · awaiting first JPEG frame'
                } elseif ($completedPreview -eq 'STOP_PREVIEW') {
                    $ui.LiveCameraImage.Source = $null
                    $ui.LiveCameraImage.Visibility = [System.Windows.Visibility]::Collapsed
                    $ui.CameraPreviewStatus.Text = 'Camera stopped · choose A/V checkbox to record video'
                }
            }
            $ui.CameraSelector.IsEnabled = (-not $script:previewActive -and -not $script:previewRequest -and $script:workerState -eq 'READY')
            $ui.CameraModeSelector.IsEnabled = (-not $script:previewActive -and -not $script:previewRequest -and $script:workerState -eq 'READY' -and $ui.CameraModeSelector.Items.Count -gt 0)
            $ui.StartPreviewButton.IsEnabled = (-not $script:previewActive -and -not $script:previewRequest -and $script:workerState -eq 'READY' -and $null -ne $ui.CameraSelector.SelectedItem -and $null -ne $ui.CameraModeSelector.SelectedItem)
            $ui.StopPreviewButton.IsEnabled = ($script:previewActive -and -not $script:previewRequest -and $script:workerState -eq 'READY')
            if ($script:previewActive) {
                $ui.CameraPreviewStatus.Text = ('{0} · frames captured {1}' -f $(if ($script:workerVideoActive) { 'RECORDING A/V' } else { 'LIVE PREVIEW' }),$state.previewFrames)
            } elseif ($state.previewError -and -not $script:previewRequest) {
                $ui.CameraPreviewStatus.Text = 'Preview diagnostic: ' + [string]$state.previewError
            }
            $script:bridgeState = $script:workerState
            $captureAckComplete = $false
            if ($script:pendingCaptureCommand -and [int]$state.lastRequestSequence -eq $script:pendingCaptureSequence) {
                $commandFailed = ([string]$state.lastCommand -eq 'COMMAND FAILED' -or $script:workerState -eq 'ERROR')
                $captureAckComplete = (
                    $commandFailed -or
                    ($script:pendingCaptureCommand -in @('START_AUDIO','START_AV') -and $script:workerState -eq 'RECORDING') -or
                    ($script:pendingCaptureCommand -in @('STOP_AUDIO','STOP_AV') -and $script:workerState -eq 'READY')
                )
            }
            if ($captureAckComplete) {
                $completed = $script:pendingCaptureCommand
                $script:pendingCaptureCommand = ''
                if ([string]$state.lastCommand -eq 'COMMAND FAILED' -or $script:workerState -eq 'ERROR') {
                    $script:bridgeCommandError = [string]$state.recordingError
                    $ui.ProbeStatus.Text = 'COMMAND FAILED: ' + $script:bridgeCommandError
                } elseif ($completed -eq 'STOP_AV' -and $state.finalizationOk -and $script:workerState -eq 'READY') {
                    $script:lastSessionPath = [string]$state.outputSessionFolder
                    $ui.FooterStatus.Text = 'MP4 VERIFIED · ' + [string]$state.outputMp4
                    $ui.ProbeStatus.Text = 'A/V finalized: ' + [string]$state.outputMp4
                    $ui.LiveCameraImage.Source = $null
                    $ui.LiveCameraImage.Visibility = [System.Windows.Visibility]::Collapsed
                } elseif ($completed -eq 'START_AV' -and $script:workerState -eq 'RECORDING') {
                    $ui.FooterStatus.Text = 'REAL A/V RECORDING · METERS DEMO · ' + [string]$state.outputAvi
                } elseif ($completed -eq 'STOP_AUDIO' -and $state.finalizationOk -and $script:workerState -eq 'READY') {
                    $script:lastSessionPath = [string]$state.outputSessionFolder
                    $ui.FooterStatus.Text = 'WAV VERIFIED · ' + [string]$state.outputWav
                    $ui.ProbeStatus.Text = 'WAV finalized: ' + [string]$state.outputWav
                } elseif ($completed -eq 'START_AUDIO' -and $script:workerState -eq 'RECORDING') {
                    $ui.FooterStatus.Text = 'REAL AUDIO RECORDING · METERS DEMO · ' + [string]$state.outputWav
                }
            }
            if ([string]$state.recordingStartedUtc) {
                $script:realRecordingStartedUtc = [datetime]::Parse([string]$state.recordingStartedUtc).ToUniversalTime()
            }
            Update-NovaRecordingTransport $script:workerState
            if ($script:pendingCaptureCommand -eq 'START_AV' -and
                $script:workerState -eq 'STARTING' -and [string]$state.cameraStartupStage) {
                $ui.ProbeStatus.Text = 'A/V START: ' + [string]$state.cameraStartupStage
            }
            # Allow recovery from a failed START only when worker state confirms idle.
            # Stop-NovaBridge independently enforces the same safety boundary.
            $ui.DisconnectBridgeButton.IsEnabled = (
                $script:workerState -in @('READY','ERROR') -and
                -not $script:workerAudioActive -and -not $script:workerVideoActive -and
                -not $script:previewActive -and -not $script:previewRequest -and
                -not $script:pendingCaptureCommand
            )
            $ui.PingBridgeButton.IsEnabled = ($script:workerState -eq 'READY' -and -not $script:pendingCaptureCommand -and -not $script:previewRequest)
            $ui.BridgeStatus.Text = 'Native audio · ' + $script:workerState
            $ui.BridgeStatus.Foreground = if ($script:workerState -eq 'ERROR') { $brushes.danger } else { $brushes.healthy }
            $ui.EngineStatus.Text = '● ENGINE INITIALIZED · AUDIO / A/V ENABLED'
            $ui.EngineStatus.Foreground = $brushes.healthy
            if (-not $script:pendingCaptureCommand -and $script:workerState -notin @('ERROR','RECORDING') -and
                -not $ui.ProbeStatus.Text.StartsWith('WAV finalized:') -and -not $ui.ProbeStatus.Text.StartsWith('A/V finalized:')) {
                $ui.ProbeStatus.Text = 'Heartbeat #' + $state.sequence + ' · last response ' + $state.lastCommand
            }
            if ([int]$state.lastRequestSequence -eq $script:bridgeLastPing -and $script:bridgeLastPing -gt 0) {
                $ui.ProbeStatus.Text = 'PING/PONG acknowledged #' + $script:bridgeLastPing
                $script:bridgeLastPing = 0
            }
            if ($script:workerState -eq 'RECORDING' -and $state.videoCaptureError) {
                $ui.ProbeStatus.Text = 'VIDEO FAILURE: STOP A/V now and preserve session files. ' + [string]$state.videoCaptureError
                $ui.FooterStatus.Text = 'VIDEO FAILED · STOP A/V TO PRESERVE WAV'
            }
            if ($script:workerState -eq 'ERROR') {
                $ui.ProbeStatus.Text = 'ENGINE ERROR: ' + [string]$state.recordingError
                $ui.FooterStatus.Text = 'ERROR · INSPECT RAW SESSION FILES BEFORE EXIT'
            }
        } catch {
            if ($_.Exception.Message -notmatch 'being used by another process') {
                $ui.BridgeStatus.Text = 'Bridge read error: ' + $_.Exception.Message
                $ui.BridgeStatus.Foreground = $brushes.danger
            }
        }
    }
    if ($script:bridgeLastHeartbeat -eq [DateTime]::MinValue) {
        if (([DateTime]::UtcNow - $script:bridgeConnectUtc).TotalSeconds -gt 90) {
            $ui.ProbeStatus.Text = 'Engine initialization timed out. Worker not killed.'
        }
    } elseif (([DateTime]::UtcNow - $script:bridgeLastHeartbeat).TotalSeconds -gt 5) {
        $ui.BridgeStatus.Text = 'STALE HEARTBEAT · DO NOT CLOSE'
        $ui.BridgeStatus.Foreground = $brushes.danger
        $ui.RecordButton.IsEnabled = $false
        $ui.DisconnectBridgeButton.IsEnabled = $false
    }
}
$ui.ConnectBridgeButton.Add_Click({
    if (-not $script:engineRoot -or $null -ne $script:bridgeProcess) { return }
    $script:bridgeDir = Join-Path ([System.IO.Path]::GetTempPath()) ('nova_bridge_'+[Guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($script:bridgeDir)
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = Join-Path $PSHOME 'powershell.exe'
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -EngineRoot "{1}" -BridgeDir "{2}" -ParentPid {3}' -f $script:bridgeHost, $script:engineRoot, $script:bridgeDir, $PID
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $script:bridgeProcess = [System.Diagnostics.Process]::Start($psi)
        if ($null -eq $script:bridgeProcess) { throw 'Could not start controller host' }
        $script:bridgeConnectUtc = [DateTime]::UtcNow
        $script:bridgeLastHeartbeat = [DateTime]::MinValue
        $script:bridgeLastSequence = 0
        $script:workerState = 'INITIALIZING'
        $script:cameraInventoryLoaded = $false
        $script:previewActive = $false
        $script:previewRequest = ''
        $ui.CameraSelector.Items.Clear()
        $ui.CameraModeSelector.Items.Clear()
        $ui.LiveCameraImage.Source = $null
        $ui.LiveCameraImage.Visibility = [System.Windows.Visibility]::Collapsed
        $script:workerAudioActive = $false
        $script:workerVideoActive = $false
        $script:sessionHasVideo = $false
        $ui.CaptureVideoCheckBox.IsChecked = $false
        $script:pendingCaptureCommand = ''
        $ui.MicrophoneSelector.Items.Clear()
        $ui.MicrophoneSelector.IsEnabled = $false
        $ui.RecordButton.IsEnabled = $false
        $ui.StopButton.IsEnabled = $false
        $ui.ConnectBridgeButton.IsEnabled = $false
        $ui.DisconnectBridgeButton.IsEnabled = $true
        $ui.BridgeStatus.Text = 'Connecting / initializing native engine...'
    } catch {
        $ui.ProbeStatus.Text = 'Connect failed: ' + $_.Exception.Message
        Stop-NovaBridge
    }
})
$ui.DisconnectBridgeButton.Add_Click({
    try { Stop-NovaBridge } catch { $ui.ProbeStatus.Text = 'Disconnect refused: ' + $_.Exception.Message }
})
$ui.MicrophoneSelector.Add_SelectionChanged({
    if ($script:workerState -eq 'READY') { Update-NovaRecordingTransport 'READY' }
})
$ui.PingBridgeButton.Add_Click({
    if ($script:bridgeState -ne 'READY') { return }
    try {
        [void](Write-NovaBridgeRequest 'PING')
        $script:bridgeLastPing = $script:bridgePingSeq
        $ui.ProbeStatus.Text = 'PING sent #' + $script:bridgeLastPing
    } catch { $ui.ProbeStatus.Text = 'PING error: ' + $_.Exception.Message }
})

$ui.CaptureVideoCheckBox.Add_Checked({
    if ($script:workerState -eq 'READY') {
        Update-NovaRecordingTransport 'READY'
        $ui.CameraPreviewStatus.Text = 'A/V will automatically prepare the selected camera on RECORD'
    }
})
$ui.CaptureVideoCheckBox.Add_Unchecked({ if ($script:workerState -eq 'READY') { Update-NovaRecordingTransport 'READY' } })
$ui.CameraModeSelector.Add_SelectionChanged({ if ($script:workerState -eq 'READY') { Update-NovaRecordingTransport 'READY' } })

$ui.GainSlider.Add_ValueChanged({
    $ui.GainValue.Text = '+{0:0} dB · APPLIED ON RECORD' -f $ui.GainSlider.Value
})

# I2 transport is driven solely by worker acknowledgements, never by a click.
$ui.RecordButton.IsEnabled = $false
$ui.StopButton.IsEnabled = $false

# Camera state is returned by worker; preview commands never enable video recording.
$ui.CameraSelector.Add_SelectionChanged({
    $ui.CameraModeSelector.Items.Clear()
    $ui.CameraModeSelector.IsEnabled = $false
    if ($script:workerState -ne 'READY' -or $script:previewActive -or $script:previewRequest -or $null -eq $ui.CameraSelector.SelectedItem) { return }
    try {
        $script:previewSequence = Write-NovaBridgeRequest 'GET_VIDEO_MODES' @{deviceName=[string]$ui.CameraSelector.SelectedItem}
        $script:previewRequest = 'GET_VIDEO_MODES'
        $ui.CameraPreviewStatus.Text = 'Discovering MJPEG modes...'
    } catch { $ui.CameraPreviewStatus.Text = 'Mode discovery failed: ' + $_.Exception.Message }
})
$ui.StartPreviewButton.Add_Click({
    if ($script:workerState -ne 'READY' -or $script:previewActive -or $script:previewRequest -or $script:pendingCaptureCommand -or $null -eq $ui.CameraModeSelector.SelectedItem) { return }
    try {
        $script:previewSequence = Write-NovaBridgeRequest 'START_PREVIEW' @{
            deviceName=[string]$ui.CameraSelector.SelectedItem
            modeKey=[string]$ui.CameraModeSelector.SelectedItem.Key
        }
        $script:previewRequest = 'START_PREVIEW'
        $ui.CameraPreviewStatus.Text = 'Opening selected camera...'
    } catch { $ui.CameraPreviewStatus.Text = 'Preview start failed: ' + $_.Exception.Message }
})
$ui.StopPreviewButton.Add_Click({
    if (-not $script:previewActive -or $script:previewRequest) { return }
    try {
        $script:previewSequence = Write-NovaBridgeRequest 'STOP_PREVIEW'
        $script:previewRequest = 'STOP_PREVIEW'
        $ui.CameraPreviewStatus.Text = 'Stopping camera and releasing DirectShow...'
    } catch { $ui.CameraPreviewStatus.Text = 'Preview stop failed: ' + $_.Exception.Message }
})
function Update-NovaCameraFrame {
    if (-not $script:previewActive -or -not $script:bridgeDir) { return }
    $framePath = Join-Path $script:bridgeDir 'preview.jpg'
    if (-not (Test-Path -LiteralPath $framePath -PathType Leaf)) { return }
    try {
        $file = Get-Item -LiteralPath $framePath
        if ($file.LastWriteTimeUtc.Ticks -eq $script:previewLastSeenTick) { return }
        # Read into memory so the JPEG file remains replaceable by worker.
        $bytes = [System.IO.File]::ReadAllBytes($framePath)
        if ($bytes.Length -lt 100) { return }
        $stream = [System.IO.MemoryStream]::new($bytes)
        try {
            $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit()
            $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmap.StreamSource = $stream
            $bitmap.EndInit()
            $bitmap.Freeze()
            $ui.LiveCameraImage.Source = $bitmap
            $ui.LiveCameraImage.Visibility = [System.Windows.Visibility]::Visible
            $script:previewLastSeenTick = $file.LastWriteTimeUtc.Ticks
            $script:previewDisplayed++
        } finally { $stream.Dispose() }
    } catch {
        # Writer may replace the file during read. Next poll retries latest frame.
        $script:previewRenderErrors++
    }
}

# Independent WPF preview renderer. Latest frame only; no queue or blocking UI waits.
$script:previewRenderTimer.Add_Tick({
    if ($script:previewActive) { Update-NovaCameraFrame }
    $now = [DateTime]::UtcNow
    $elapsed = ($now - $script:previewLastMetricsUtc).TotalSeconds
    if ($elapsed -lt 1.25) { return }
    $state = $script:previewLatestState
    if ($script:previewActive -and $null -ne $state) {
        $captured = [long]$state.previewFrames
        $published = [long]$state.previewPublished
        $displayed = [long]$script:previewDisplayed
        $captureRate = [Math]::Max(0,($captured - $script:previewMetricsBaseline.captured) / $elapsed)
        $publishRate = [Math]::Max(0,($published - $script:previewMetricsBaseline.published) / $elapsed)
        $displayRate = [Math]::Max(0,($displayed - $script:previewMetricsBaseline.displayed) / $elapsed)
        $ui.PreviewMetrics.Text = ('CAPTURE {0:N1} fps  |  TRANSPORT {1:N1} fps  |  DISPLAY {2:N1} fps' -f $captureRate,$publishRate,$displayRate)
        $ui.PreviewMetrics.ToolTip = ('Frames captured: {0}; published: {1}; displayed: {2}; publish errors: {3}; display errors: {4}' -f $captured,$published,$displayed,[long]$state.previewWriteFailures,$script:previewRenderErrors)
        $script:previewMetricsBaseline = @{captured=$captured;published=$published;displayed=$displayed}
    } else {
        $ui.PreviewMetrics.Text = 'PREVIEW OFF · SOURCE NOT CONNECTED'
        $ui.PreviewMetrics.ToolTip = 'Camera preview disabled'
        $script:previewMetricsBaseline = @{captured=0L;published=0L;displayed=0L}
        $script:previewDisplayed = 0
    }
    $script:previewLastMetricsUtc = $now
})

$ui.RecordButton.Add_Click({
    if ($script:workerState -ne 'READY' -or $script:pendingCaptureCommand -or $script:previewRequest) { return }
    if ($null -eq $ui.MicrophoneSelector.SelectedItem) {
        $ui.ProbeStatus.Text = 'Select the microphone explicitly before recording.'
        return
    }
    $selected = $ui.MicrophoneSelector.SelectedItem
    try {
        $isAv = ($ui.CaptureVideoCheckBox.IsChecked -eq $true)
        if ($isAv -and ($null -eq $ui.CameraSelector.SelectedItem -or $null -eq $ui.CameraModeSelector.SelectedItem)) {
            throw 'Select the camera and mode before recording A/V.'
        }
        if (-not $isAv -and $script:previewActive) {
            throw 'STOP PREVIEW before audio-only recording.'
        }
        $command = if ($isAv) { 'START_AV' } else { 'START_AUDIO' }
        $args = @{deviceId=[int]$selected.Id; gainDb=[double]$ui.GainSlider.Value}
        if ($isAv) {
            $args.deviceName = [string]$ui.CameraSelector.SelectedItem
            $args.modeKey = [string]$ui.CameraModeSelector.SelectedItem.Key
        }
        $seq = Write-NovaBridgeRequest $command $args
        $script:pendingCaptureCommand = $command
        $script:pendingCaptureSequence = $seq
        $script:pendingCaptureUtc = [DateTime]::UtcNow
        $ui.ProbeStatus.Text = $(if ($isAv) { 'START A/V requested · preparing camera and audio' } else { 'START AUDIO requested · waiting for engine confirmation' })
        Update-NovaRecordingTransport 'STARTING'
    } catch { $ui.ProbeStatus.Text = 'START failed to send: ' + $_.Exception.Message }
})
$ui.StopButton.Add_Click({
    if ($script:workerState -ne 'RECORDING' -or $script:pendingCaptureCommand) { return }
    try {
        $command = if ($script:sessionHasVideo) { 'STOP_AV' } else { 'STOP_AUDIO' }
        $seq = Write-NovaBridgeRequest $command
        $script:pendingCaptureCommand = $command
        $script:pendingCaptureSequence = $seq
        $script:pendingCaptureUtc = [DateTime]::UtcNow
        $ui.ProbeStatus.Text = $(if ($script:sessionHasVideo) { 'STOP A/V requested · finalizing AVI, WAV and MP4' } else { 'STOP AUDIO requested · finalizing WAV' })
        Update-NovaRecordingTransport 'STOPPING'
    } catch { $ui.ProbeStatus.Text = 'STOP failed to send: ' + $_.Exception.Message }
})

$bars = New-Object 'System.Collections.Generic.List[System.Windows.Shapes.Rectangle]'
for ($i=0; $i -lt 36; $i++) {
    $rect = New-Object System.Windows.Shapes.Rectangle
    $rect.Width = 8
    $rect.Height = 10
    $rect.Margin = [System.Windows.Thickness]::new(0,0,3,0)
    $rect.RadiusX = 1
    $rect.RadiusY = 1
    $rect.Fill = if ($i -lt 23) { $brushes.low } elseif ($i -lt 30) { $brushes.mid } else { $brushes.high }
    $rect.Opacity = 0.15
    [void]$ui.LevelBars.Children.Add($rect)
    $bars.Add($rect)
}

# Prebuilt bars; only height/opacity change on the Dispatcher timer.
$spectrum = New-Object 'System.Collections.Generic.List[System.Windows.Shapes.Rectangle]'
for ($i = 0; $i -lt 40; $i++) {
    $rect = New-Object System.Windows.Shapes.Rectangle
    $rect.Width = 8
    $rect.Height = 12
    $rect.Margin = [System.Windows.Thickness]::new(0,0,3,0)
    $rect.RadiusX = 2
    $rect.RadiusY = 2
    $rect.Fill = if ($i -lt 13) { New-Brush '#9282ED' } elseif ($i -lt 27) { New-Brush '#60C5DA' } else { New-Brush '#69D7A9' }
    $rect.Opacity = 0.7
    [void]$ui.SpectrumBars.Children.Add($rect)
    $spectrum.Add($rect)
}

$script:demoTimer.Add_Tick({
    Complete-NovaEngineProbe
    $script:bridgePollTicks++
    if ($script:bridgePollTicks % 6 -eq 0) { Update-NovaBridge }
    # Camera preview has its own ~25 Hz timer; do not couple frame rendering to demo tick.
    $script:tickCount++
    $beat = 0.25 + 0.45 * [Math]::Abs([Math]::Sin($script:tickCount * 0.13))
    $noise = $script:generator.NextDouble() * 0.32
    $intensity = [Math]::Min(1, $beat + $noise)
    $threshold = [int][Math]::Floor($intensity * 36)
    for ($i=0; $i -lt $bars.Count; $i++) {
        $bars[$i].Opacity = if ($i -lt $threshold) { 0.95 } else { 0.13 }
    }
    $points = [System.Windows.Media.PointCollection]::new()
    for ($i=0; $i -le 110; $i++) {
        $envelope = (0.18 + 0.70*[Math]::Abs([Math]::Sin(($i + $script:tickCount * 2) * 0.043)))
        $wave = [Math]::Sin(($i + $script:tickCount * 3) * 0.42) * 35 * $envelope * $intensity
        $points.Add([System.Windows.Point]::new([double]$i, [double](50 + $wave)))
    }
    $ui.WaveformLine.Points = $points
    $labPoints = [System.Windows.Media.PointCollection]::new()
    for ($i = 0; $i -le 110; $i++) {
        $env = [Math]::Abs([Math]::Sin(($i + $script:tickCount) * 0.075))
        $v = [Math]::Sin(($i + $script:tickCount * 2.4) * 0.43) * (4 + 25 * $env * $intensity)
        $labPoints.Add([System.Windows.Point]::new([double]$i, [double](30 + $v)))
    }
    $ui.LabWaveform.Points = $labPoints
    # Independent demonstration bands. They are not derived from microphone audio.
    $bass = 0.2 + 0.8 * [Math]::Abs([Math]::Sin($script:tickCount * 0.095))
    $mids = 0.2 + 0.8 * [Math]::Abs([Math]::Sin($script:tickCount * 0.17 + 1))
    $treble = 0.2 + 0.8 * [Math]::Abs([Math]::Sin($script:tickCount * 0.23 + 2))
    for ($i = 0; $i -lt $spectrum.Count; $i++) {
        $region = if ($i -lt 13) { $bass } elseif ($i -lt 27) { $mids } else { $treble }
        $variation = 0.32 + 0.68 * [Math]::Abs([Math]::Sin($i * 0.5 + $script:tickCount * 0.08))
        $spectrum[$i].Height = 8 + 66 * $region * $variation
    }
    $ui.JawGlow.Opacity = 0.15 + 0.85 * $bass
    $ui.EyesGlow.Opacity = 0.15 + 0.85 * $mids
    $ui.HaloGlow.Opacity = 0.12 + 0.82 * $treble
    $ui.RmsPeakReadout.Text = 'RMS {0:N0} / PEAK {1:N0}' -f (-34 + 22 * $intensity), (-42 + 41*$intensity)
    $ui.PeakReadout.Text = 'DEMO PEAK  {0:N1} dBFS' -f (-42 + $intensity*41)
    $clip = $intensity -gt 0.96
    if ($clip) { $script:clipHold = 6 }
    if ($script:clipHold -gt 0) { $script:clipHold-- }
    $ui.ClipReadout.Text = if ($script:clipHold -gt 0) { '● DEMO CLIP' } else { 'NO CLIP' }
    $ui.ClipReadout.Foreground = if ($script:clipHold -gt 0) { $brushes.danger } else { $brushes.healthy }
    $headBrush = if ($script:clipHold -gt 0) { $brushes.headClip } elseif ($intensity -gt 0.7) { $brushes.headLoud } else { $brushes.head }
    $ui.CompactHeadOutline.Fill = $headBrush
    $ui.LargeHeadOutline.Fill = $headBrush
    $ui.CompactGlow.Opacity = 0.25 + $intensity * 0.75
    $ui.LargeGlow.Opacity = 0.25 + $intensity * 0.75
    $ui.HeadSignalStatus.Text = if ($script:clipHold -gt 0) { '● DEMO CLIP' } else { '● HEALTHY' }
    $ui.HeadSignalStatus.Foreground = if ($script:clipHold -gt 0) { $brushes.danger } else { $brushes.healthy }
    if ($script:workerState -eq 'RECORDING' -and $script:realRecordingStartedUtc -ne [DateTime]::MinValue) {
        $elapsed = [DateTime]::UtcNow - $script:realRecordingStartedUtc
        $ui.ElapsedText.Text = '{0:00}:{1:00}:{2:00}' -f [Math]::Floor($elapsed.TotalHours), $elapsed.Minutes, $elapsed.Seconds
    }
})

# I2-R1 fail-closed rule: the X button is NEVER a controller disconnect.
# An explicit DISCONNECT must first succeed (available only while READY).
# This avoids relying on potentially stale UI state during active capture.
$window.Add_Closing([System.ComponentModel.CancelEventHandler]{
    param($sender, $eventArgs)
    if ($null -ne $script:bridgeProcess) {
        $eventArgs.Cancel = $true
        $ui.ProbeStatus.Text = 'Close blocked: STOP recording / STOP PREVIEW, then DISCONNECT first.'
        [System.Windows.MessageBox]::Show(
            'Controller is still attached. To close NOVA Studio safely: STOP the recording and wait for verified finalization, STOP PREVIEW if running, then click DISCONNECT. Closing with an attached controller is blocked.',
            'NOVA Studio - protected shutdown',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning) | Out-Null
    }
})
$window.Add_Closed({
    try { Stop-NovaBridge } catch {
        # Preserve worker and IPC when shutdown cannot be confirmed.
        Write-Warning ('Worker preserved: ' + $_.Exception.Message)
    }
    $script:demoTimer.Stop()
    $script:previewRenderTimer.Stop()
    if ($null -ne $script:probeProcess) {
        try { if (-not $script:probeProcess.HasExited) { $script:probeProcess.Kill() } } catch {}
        try { $script:probeProcess.Dispose() } catch {}
    }
    if ($script:probeFile -and (Test-Path -LiteralPath $script:probeFile)) {
        Remove-Item -LiteralPath $script:probeFile -Force -ErrorAction SilentlyContinue
    }
})
Set-Workspace 'Capture'
$script:demoTimer.Start()
$script:previewRenderTimer.Start()
[void]$window.ShowDialog()
