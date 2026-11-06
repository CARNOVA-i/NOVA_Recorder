Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# =====================================================================
# NOVA RECORDER v2.2
#
# Portable Windows microphone recorder
#
# Features:
#   - Explicit recording-device selection
#   - Native Windows waveIn capture
#   - Live post-gain level meter
#   - Adjustable digital gain: 0 to +18 dB
#   - Clipping indicator
#   - 16-bit PCM WAV output
#   - Timestamped recordings
#   - Optional 1080p30 MJPEG webcam capture via portable FFmpeg
#   - Audio and video saved as separate files for this integration stage
#   - No installed external libraries required
# =====================================================================


# Load the existing native C# classes and compile them before application initialization.
. (Join-Path $PSScriptRoot "Engine\NovaNative.ps1")

# =====================================================================
# Directories
# =====================================================================

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$recordingsDirectory = Join-Path $scriptDirectory "Recordings"
$ffmpegPath = Join-Path $scriptDirectory "tools\ffmpeg\ffmpeg.exe"

if (-not (Test-Path -LiteralPath $recordingsDirectory)) {
    New-Item -ItemType Directory -Path $recordingsDirectory | Out-Null
}

$script:ffmpegAvailable = Test-Path -LiteralPath $ffmpegPath


# =====================================================================
# Application state
# =====================================================================

$script:recorder = New-Object NovaWaveRecorder

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


# =====================================================================
# Helpers
# =====================================================================


. (Join-Path $PSScriptRoot "Engine\NovaEngine.ps1")
. (Join-Path $PSScriptRoot "Engine\NovaSession.ps1")


# Video lifecycle functions; explicit preview target supplied by UI callers.
. (Join-Path $PSScriptRoot "Engine\NovaVideo.ps1")


# WP-01B.2b-I2A: controller startup orchestration (STOP remains in WinForms).
. (Join-Path $PSScriptRoot "Engine\NovaController.ps1")

function Update-NovaVideoModes {
    $videoModeCombo.Items.Clear()

    if (-not $videoCombo.SelectedItem) {
        $videoModeCombo.Enabled = $false
        return
    }

    $deviceName = [string]$videoCombo.SelectedItem
    $modes = Get-NovaVideoModes -DeviceName $deviceName

    foreach ($mode in $modes) {
        [void]$videoModeCombo.Items.Add($mode)
    }

    if ($videoModeCombo.Items.Count -gt 0) {
        $videoModeCombo.SelectedIndex = 0
        $videoModeCombo.Enabled = $true
    }
    else {
        $videoModeCombo.Enabled = $false
    }
}

# =====================================================================
# Main window
# =====================================================================

$form = New-Object System.Windows.Forms.Form

$form.Text = "Nova Recorder v2.2"

$form.Size = New-Object System.Drawing.Size(580, 940)

$form.StartPosition = "CenterScreen"

$form.FormBorderStyle = "FixedDialog"

$form.MaximizeBox = $false

$form.MinimizeBox = $true

$form.BackColor = [System.Drawing.Color]::FromArgb(28, 30, 34)


# =====================================================================
# Title
# =====================================================================

$titleLabel = New-Object System.Windows.Forms.Label

$titleLabel.Text = "NOVA RECORDER"

$titleLabel.ForeColor = [System.Drawing.Color]::White

$titleLabel.Font = New-Object System.Drawing.Font(
    "Segoe UI",
    20,
    [System.Drawing.FontStyle]::Bold
)

$titleLabel.AutoSize = $true

$titleLabel.Location = New-Object System.Drawing.Point(150, 20)

$form.Controls.Add($titleLabel)


# =====================================================================
# Microphone label
# =====================================================================

$micLabel = New-Object System.Windows.Forms.Label

$micLabel.Text = "Microphone"

$micLabel.ForeColor = [System.Drawing.Color]::Gainsboro

$micLabel.Font = New-Object System.Drawing.Font(
    "Segoe UI",
    10
)

$micLabel.AutoSize = $true

$micLabel.Location = New-Object System.Drawing.Point(50, 80)

$form.Controls.Add($micLabel)


# =====================================================================
# Microphone dropdown
# =====================================================================

$deviceCombo = New-Object System.Windows.Forms.ComboBox

$deviceCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$deviceCombo.Size = New-Object System.Drawing.Size(350, 30)

$deviceCombo.Location = New-Object System.Drawing.Point(50, 104)

$deviceCombo.Font = New-Object System.Drawing.Font(
    "Segoe UI",
    10
)

$form.Controls.Add($deviceCombo)


# =====================================================================
# Refresh devices
# =====================================================================

$refreshButton = New-Object System.Windows.Forms.Button

$refreshButton.Text = "Refresh"

$refreshButton.Size = New-Object System.Drawing.Size(85, 29)

$refreshButton.Location = New-Object System.Drawing.Point(415, 103)

$form.Controls.Add($refreshButton)


# =====================================================================
# Video capture controls
# =====================================================================

$videoLabel = New-Object System.Windows.Forms.Label
$videoLabel.Text = "Video source"
$videoLabel.ForeColor = [System.Drawing.Color]::Gainsboro
$videoLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$videoLabel.AutoSize = $true
$videoLabel.Location = New-Object System.Drawing.Point(50, 145)
$form.Controls.Add($videoLabel)

$videoCombo = New-Object System.Windows.Forms.ComboBox
$videoCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$videoCombo.Size = New-Object System.Drawing.Size(350, 30)
$videoCombo.Location = New-Object System.Drawing.Point(50, 169)
$videoCombo.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Controls.Add($videoCombo)

$videoCheckBox = New-Object System.Windows.Forms.CheckBox
$videoCheckBox.Text = "Capture"
$videoCheckBox.ForeColor = [System.Drawing.Color]::Gainsboro
$videoCheckBox.AutoSize = $true
$videoCheckBox.Location = New-Object System.Drawing.Point(415, 172)
$videoCheckBox.Checked = $true
$form.Controls.Add($videoCheckBox)

$videoModeLabel = New-Object System.Windows.Forms.Label
$videoModeLabel.Text = "Video mode"
$videoModeLabel.Location = New-Object System.Drawing.Point(50, 210)
$videoModeLabel.Size = New-Object System.Drawing.Size(100, 20)
$videoModeLabel.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($videoModeLabel)

$previewPanel = New-Object System.Windows.Forms.Panel
$previewPanel.Size = New-Object System.Drawing.Size(350, 180)
$previewPanel.Location = New-Object System.Drawing.Point(80, 280)
$previewPanel.BackColor = [System.Drawing.Color]::FromArgb(18, 20, 24)
$previewPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

$form.Controls.Add($previewPanel)

$previewBox = New-Object System.Windows.Forms.PictureBox
$previewBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$previewBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$previewBox.BackColor = [System.Drawing.Color]::Black

$previewPanel.Controls.Add($previewBox)

$videoModeCombo = New-Object System.Windows.Forms.ComboBox
$videoModeCombo.Location = New-Object System.Drawing.Point(50, 234)
$videoModeCombo.Size = New-Object System.Drawing.Size(350, 24)
$videoModeCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$videoModeCombo.DisplayMember = "Display"
$form.Controls.Add($videoModeCombo)

$videoCombo.Add_SelectedIndexChanged({
    Update-NovaVideoModes
})


# =====================================================================
# Input meter label
# =====================================================================

$levelLabel = New-Object System.Windows.Forms.Label

$levelLabel.Text = "Input level (post-gain)"

$levelLabel.ForeColor = [System.Drawing.Color]::Gainsboro

$levelLabel.Font = New-Object System.Drawing.Font(
    "Segoe UI",
    10
)

$levelLabel.AutoSize = $true

$levelLabel.Location = New-Object System.Drawing.Point(240, 500)

$form.Controls.Add($levelLabel)


# =====================================================================
# Clip indicator
# =====================================================================

$clipLabel = New-Object System.Windows.Forms.Label

$clipLabel.Text = "CLIP"

$clipLabel.ForeColor = [System.Drawing.Color]::DimGray

$clipLabel.Font = New-Object System.Drawing.Font(
    "Segoe UI",
    9,
    [System.Drawing.FontStyle]::Bold
)

$clipLabel.AutoSize = $true

$clipLabel.Location = New-Object System.Drawing.Point(472, 485)

$form.Controls.Add($clipLabel)


# =====================================================================
# Input level bar (HEAD)
# =====================================================================

$headMeter = New-Object CyberHeadMeter

$headMeter.Size = New-Object System.Drawing.Size(120, 120)

$headMeter.Location = New-Object System.Drawing.Point(423, 500)

$headMeter.Level = 0

$headMeter.Clipping = $false

$form.Controls.Add($headMeter)


# =====================================================================
# Gain label
# =====================================================================

$gainTitleLabel = New-Object System.Windows.Forms.Label

$gainTitleLabel.Text = "Recording gain"

$gainTitleLabel.ForeColor = [System.Drawing.Color]::Gainsboro

$gainTitleLabel.Font = New-Object System.Drawing.Font(
    "Segoe UI",
    10
)

$gainTitleLabel.AutoSize = $true

$gainTitleLabel.Location = New-Object System.Drawing.Point(45, 520)

$form.Controls.Add($gainTitleLabel)


# =====================================================================
# Gain value
# =====================================================================

$gainValueLabel = New-Object System.Windows.Forms.Label

$gainValueLabel.Text = "+16 dB"

$gainValueLabel.ForeColor = [System.Drawing.Color]::White

$gainValueLabel.Font = New-Object System.Drawing.Font(
    "Segoe UI",
    10,
    [System.Drawing.FontStyle]::Bold
)

$gainValueLabel.AutoSize = $true

$gainValueLabel.Location = New-Object System.Drawing.Point(375, 500)

$form.Controls.Add($gainValueLabel)


# =====================================================================
# Gain slider
# =====================================================================

$gainSlider = New-Object System.Windows.Forms.TrackBar

$gainSlider.Minimum = 0

$gainSlider.Maximum = 32

$gainSlider.Value = 16

$gainSlider.TickFrequency = 4

$gainSlider.SmallChange = 1

$gainSlider.LargeChange = 4

$gainSlider.Size = New-Object System.Drawing.Size(370, 38)

$gainSlider.Location = New-Object System.Drawing.Point(40, 540)

$form.Controls.Add($gainSlider)


# Gain scale labels

$gainZeroLabel = New-Object System.Windows.Forms.Label
$gainZeroLabel.Text = "0"
$gainZeroLabel.ForeColor = [System.Drawing.Color]::Gray
$gainZeroLabel.AutoSize = $true
$gainZeroLabel.Location = New-Object System.Drawing.Point(48, 590)
$form.Controls.Add($gainZeroLabel)


$gainSixLabel = New-Object System.Windows.Forms.Label
$gainSixLabel.Text = "+8"
$gainSixLabel.ForeColor = [System.Drawing.Color]::Gray
$gainSixLabel.AutoSize = $true
$gainSixLabel.Location = New-Object System.Drawing.Point(128, 590)
$form.Controls.Add($gainSixLabel)


$gainTwelveLabel = New-Object System.Windows.Forms.Label
$gainTwelveLabel.Text = "+16"
$gainTwelveLabel.ForeColor = [System.Drawing.Color]::Gray
$gainTwelveLabel.AutoSize = $true
$gainTwelveLabel.Location = New-Object System.Drawing.Point(212, 590)
$form.Controls.Add($gainTwelveLabel)


$gainEighteenLabel = New-Object System.Windows.Forms.Label
$gainEighteenLabel.Text = "+24"
$gainEighteenLabel.ForeColor = [System.Drawing.Color]::Gray
$gainEighteenLabel.AutoSize = $true
$gainEighteenLabel.Location = New-Object System.Drawing.Point(296, 590)
$form.Controls.Add($gainEighteenLabel)


$gainTwentyFourLabel = New-Object System.Windows.Forms.Label

$gainTwentyFourLabel.Text = "+32 dB"
$gainTwentyFourLabel.ForeColor = [System.Drawing.Color]::Gray
$gainTwentyFourLabel.AutoSize = $true
$gainTwentyFourLabel.Location = New-Object System.Drawing.Point(381, 590)

$form.Controls.Add($gainTwentyFourLabel)


# Set initial +16 dB gain.

$script:recorder.SetGainDb([double]$gainSlider.Value)


# =====================================================================
# Status
# =====================================================================

$statusLabel = New-Object System.Windows.Forms.Label

$statusLabel.Text = "Microphone ready"

$statusLabel.ForeColor = [System.Drawing.Color]::LightGreen

$statusLabel.Font = New-Object System.Drawing.Font(
    "Segoe UI",
    11
)

$statusLabel.AutoSize = $true

$statusLabel.Location = New-Object System.Drawing.Point(230, 820)

$form.Controls.Add($statusLabel)


# =====================================================================
# Timer
# =====================================================================

$timerLabel = New-Object System.Windows.Forms.Label

$timerLabel.Text = "00:00:00"

$timerLabel.ForeColor = [System.Drawing.Color]::White

$timerLabel.Font = New-Object System.Drawing.Font(
    "Consolas",
    24,
    [System.Drawing.FontStyle]::Bold
)

$timerLabel.AutoSize = $true

$timerLabel.Location = New-Object System.Drawing.Point(185, 640)

$form.Controls.Add($timerLabel)


# =====================================================================
# Record button
# =====================================================================

$recordButton = New-Object System.Windows.Forms.Button

$recordButton.Text = "RECORD"

$recordButton.Size = New-Object System.Drawing.Size(145, 48)

$recordButton.Location = New-Object System.Drawing.Point(105, 695)

$recordButton.Font = New-Object System.Drawing.Font(
    "Segoe UI",
    11,
    [System.Drawing.FontStyle]::Bold
)

$recordButton.BackColor = [System.Drawing.Color]::FromArgb(
    180,
    40,
    40
)

$recordButton.ForeColor = [System.Drawing.Color]::White

$recordButton.FlatStyle = "Flat"

$form.Controls.Add($recordButton)


# =====================================================================
# Stop button
# =====================================================================

$stopButton = New-Object System.Windows.Forms.Button

$stopButton.Text = "STOP"

$stopButton.Size = New-Object System.Drawing.Size(145, 48)

$stopButton.Location = New-Object System.Drawing.Point(300, 695)

$stopButton.Font = New-Object System.Drawing.Font(
    "Segoe UI",
    11,
    [System.Drawing.FontStyle]::Bold
)

$stopButton.BackColor = [System.Drawing.Color]::FromArgb(
    65,
    68,
    75
)

$stopButton.ForeColor = [System.Drawing.Color]::White

$stopButton.FlatStyle = "Flat"

$stopButton.Enabled = $false

$form.Controls.Add($stopButton)


# =====================================================================
# Open recordings folder button
# =====================================================================

$folderButton = New-Object System.Windows.Forms.Button

$folderButton.Text = "Open Recordings Folder"

$folderButton.Size = New-Object System.Drawing.Size(205, 30)

$folderButton.Location = New-Object System.Drawing.Point(175, 755)

$form.Controls.Add($folderButton)


# =====================================================================
# Load / refresh recording devices
# =====================================================================

function Update-DeviceList {

    $previousName = $null

    if ($null -ne $deviceCombo.SelectedItem) {
        $previousName = $deviceCombo.SelectedItem.Name
    }

    $deviceCombo.Items.Clear()

    $devices = [NovaWaveRecorder]::GetDevices()
    $fullAudioNames = @(Get-NovaAudioDeviceNames)

    foreach ($device in $devices) {

        $legacyKey = ConvertTo-NovaDeviceMatchKey -Name $device.Name

        foreach ($fullName in $fullAudioNames) {

            $fullKey = ConvertTo-NovaDeviceMatchKey -Name $fullName

            if (
                $fullKey.StartsWith($legacyKey) -or
                $legacyKey.StartsWith($fullKey)
            ) {
                $device.Name = $fullName
                break
            }
        }

        [void]$deviceCombo.Items.Add($device)
    }

    if ($deviceCombo.Items.Count -eq 0) {

        $statusLabel.Text = "No microphones found"
        $statusLabel.ForeColor = [System.Drawing.Color]::OrangeRed

        $recordButton.Enabled = $false

        return
    }

    $selected = $false

    if ($null -ne $previousName) {

        for ($i = 0; $i -lt $deviceCombo.Items.Count; $i++) {

            if ($deviceCombo.Items[$i].Name -eq $previousName) {

                $deviceCombo.SelectedIndex = $i

                $selected = $true

                break
            }
        }
    }

    if (-not $selected) {
        $deviceCombo.SelectedIndex = 0
    }

    $recordButton.Enabled = $true

    $statusLabel.Text = "Microphone ready"

    $statusLabel.ForeColor = [System.Drawing.Color]::LightGreen
}


function Update-VideoDeviceList {

    $previousName = $null

    if ($null -ne $videoCombo.SelectedItem) {
        $previousName = [string]$videoCombo.SelectedItem
    }

    $videoCombo.Items.Clear()

    if (-not $script:ffmpegAvailable) {
        $videoCombo.Enabled = $false
        $videoCheckBox.Checked = $false
        $videoCheckBox.Enabled = $false
        return
    }

    $videoCheckBox.Enabled = $true

    try {
        $devices = @(Get-NovaVideoDevices)
    }
    catch {
        $devices = @()
    }

    foreach ($device in $devices) {
        [void]$videoCombo.Items.Add($device)
    }

    if ($videoCombo.Items.Count -eq 0) {
        $videoCombo.Enabled = $false
        $videoCheckBox.Checked = $false
        return
    }

    $videoCombo.Enabled = $true

    $selected = $false

    if ($null -ne $previousName) {
        for ($i = 0; $i -lt $videoCombo.Items.Count; $i++) {
            if ([string]$videoCombo.Items[$i] -eq $previousName) {
                $videoCombo.SelectedIndex = $i
                $selected = $true
                break
            }
        }
    }

    if (-not $selected) {
        $videoCombo.SelectedIndex = 0
    }

Update-NovaVideoModes
}


function Start-LivePreview {

    if ($script:recording) {
        return
    }

    if ($null -eq $deviceCombo.SelectedItem) {
        return
    }

    try {

        $script:recorder.SetGainDb(
            [double]$gainSlider.Value
        )

        $script:recorder.StartPreview(
            $deviceCombo.SelectedItem.Id
        )

        $statusLabel.Text = "LIVE PREVIEW"
        $statusLabel.ForeColor = [System.Drawing.Color]::MediumPurple
    }
    catch {

        $statusLabel.Text = "Preview unavailable"
        $statusLabel.ForeColor = [System.Drawing.Color]::OrangeRed
    }
}


function Stop-LivePreview {

    try {

        if ($script:recorder.IsPreviewing) {
            $script:recorder.StopPreview()
        }
    }
    catch {
    }

    $headMeter.Level = 0
    $headMeter.Clipping = $false
}

# =====================================================================
# Gain slider change
# =====================================================================

$gainSlider.Add_ValueChanged({

    $gain = [double]$gainSlider.Value

    $script:recorder.SetGainDb($gain)

    $gainValueLabel.Text = "+$($gainSlider.Value) dB"
})


# =====================================================================
# GUI update timer
# =====================================================================

$uiTimer = New-Object System.Windows.Forms.Timer

$uiTimer.Interval = 100


$uiTimer.Add_Tick({

    if ($script:recording -or $script:recorder.IsPreviewing) {

        # -------------------------------------------------------------
        # Elapsed time
        # -------------------------------------------------------------

        if ($null -ne $script:recordingStart) {

            $elapsed = (Get-Date) - $script:recordingStart

            $hours = [Math]::Floor($elapsed.TotalHours)

            $timerLabel.Text = "{0:00}:{1:00}:{2:00}" -f `
                $hours,
                $elapsed.Minutes,
                $elapsed.Seconds
        }


        # -------------------------------------------------------------
        # Live post-gain level
        # -------------------------------------------------------------

        try {

            $peak = $script:recorder.GetPeakPercent()

            if ($peak -lt 0) {
                $peak = 0
            }

            if ($peak -gt 100) {
                $peak = 100
            }

            $headMeter.Level = $peak


            if ($script:recorder.GetAndResetClipping()) {

            $clipLabel.ForeColor = [System.Drawing.Color]::Red
            $headMeter.Clipping = $true
            }
            else {

                $clipLabel.ForeColor = [System.Drawing.Color]::DimGray
                $headMeter.Clipping = $false
            }
        }
        catch {

            $headMeter.Level = 0
            $headMeter.Clipping = $false
        }
    }
    else {

        $headMeter.Level = 0
        $headMeter.Clipping = $false

        $clipLabel.ForeColor = [System.Drawing.Color]::DimGray
    }
})


# =====================================================================
# Refresh button
# =====================================================================

$refreshButton.Add_Click({

    if ($script:recording) {
        return
    }

    Update-DeviceList
    Update-VideoDeviceList
})


# =====================================================================
# RECORD
# =====================================================================

$recordButton.Add_Click({

    if ($script:recording -or $script:recordingStarting -or $script:recordingStopping) {
        return
    }


    if ($null -eq $deviceCombo.SelectedItem) {

        [System.Windows.Forms.MessageBox]::Show(
            "Select a microphone first.",
            "Nova Recorder",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        return
    }


    $device = $deviceCombo.SelectedItem

    if ($videoCheckBox.Checked -and $null -eq $videoCombo.SelectedItem) {

        [System.Windows.Forms.MessageBox]::Show(
            "Video capture is enabled, but no usable camera is selected.",
            "Nova Recorder",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        return
    }

    $script:recordingStarting = $true
    try {
        Start-NovaRecording `
            -AudioDevice $device `
            -GainDb ([double]$gainSlider.Value) `
            -VideoEnabled ([bool]$videoCheckBox.Checked) `
            -VideoDeviceName ([string]$videoCombo.SelectedItem) `
            -VideoMode $videoModeCombo.SelectedItem `
            -PreviewTarget $previewBox `
            -PumpEvents { [System.Windows.Forms.Application]::DoEvents() } `
            -OnCameraStarting {
                $statusLabel.Text = "STARTING CAMERA..."
                $statusLabel.ForeColor = [System.Drawing.Color]::Goldenrod
            }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "Nova Recorder",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )

        $statusLabel.Text = "READY"
        $statusLabel.ForeColor = [System.Drawing.Color]::LightGray

        if (
            $videoCheckBox.Checked -and
            $null -ne $videoCombo.SelectedItem -and
            $null -ne $videoModeCombo.SelectedItem
        ) {
            try {
                Start-NovaVideoPreview `
                    -DeviceName ([string]$videoCombo.SelectedItem) `
                    -Mode $videoModeCombo.SelectedItem `
                    -PreviewTarget $previewBox
            }
            catch {
                Write-Host "Camera preview restart after failed recording start failed: $($_.Exception.Message)"
            }
        }
        return
    }
    finally {
        $script:recordingStarting = $false
    }


    $script:recording = $true

    $script:recordingStart = Get-Date


    $statusLabel.Text = "RECORDING"

    $statusLabel.ForeColor = [System.Drawing.Color]::Tomato


    $timerLabel.Text = "00:00:00"

    $headMeter.Level = 0
    $headMeter.Clipping = $false

    $clipLabel.ForeColor = [System.Drawing.Color]::DimGray


    $recordButton.Enabled = $false

    $stopButton.Enabled = $true

    $deviceCombo.Enabled = $false

    $videoCombo.Enabled = $false
    $videoCheckBox.Enabled = $false

    $refreshButton.Enabled = $false


    # Gain remains adjustable while recording.

    $uiTimer.Start()
})


# =====================================================================
# STOP
# =====================================================================

$stopButton.Add_Click({

    if (-not $script:recording -or $script:recordingStarting -or $script:recordingStopping) {
        return
    }


    $uiTimer.Stop()


    # Controller owns STOP, metadata and MP4 finalization. UI owns presentation.
    $script:recordingStopping = $true
    try {
        $stopResult = Stop-NovaRecording `
            -AudioDevice $deviceCombo.SelectedItem `
            -GainDb ([double]$gainSlider.Value) `
            -VideoDevice $videoCombo.SelectedItem
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Recording finalization did not complete: $($_.Exception.Message)`n`nCheck the session's raw files before closing.",
            "Nova Recorder",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }
    finally {
        $script:recordingStopping = $false
    }

    $videoStopError = $stopResult.VideoStopError

    if ($null -ne $stopResult.AudioStopError) {
        [System.Windows.Forms.MessageBox]::Show(
            $stopResult.AudioStopError,
            "Nova Recorder",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }

    # Restart idle camera preview after recording is fully finished
    if (
        $videoCheckBox.Checked -and
        $null -ne $videoCombo.SelectedItem -and
        $null -ne $videoModeCombo.SelectedItem
    ) {
        try {
            Start-NovaVideoPreview `
                -DeviceName ([string]$videoCombo.SelectedItem) `
                -Mode $videoModeCombo.SelectedItem `
                -PreviewTarget $previewBox
        }
        catch {
            Write-Host "Camera preview restart failed: $($_.Exception.Message)"
        }
    }

    $headMeter.Level = 0
    $headMeter.Clipping = $false

    $clipLabel.ForeColor = [System.Drawing.Color]::DimGray


    $statusLabel.Text = "Recording saved"

    $statusLabel.ForeColor = [System.Drawing.Color]::LightGreen


    $recordButton.Enabled = $true

    $stopButton.Enabled = $false

    $deviceCombo.Enabled = $true

    $videoCheckBox.Enabled = $script:ffmpegAvailable
    $videoCombo.Enabled = ($script:ffmpegAvailable -and $videoCombo.Items.Count -gt 0)

    $refreshButton.Enabled = $true


    if (Test-Path -LiteralPath $script:currentFile) {

        $fileInfo = Get-Item -LiteralPath $script:currentFile

        $sizeKB = [Math]::Round(
            $fileInfo.Length / 1KB,
            1
        )


        $formatText = "$($script:recorder.SampleRate) Hz"

        if ($script:recorder.Channels -eq 1) {
            $formatText += ", Mono"
        }
        else {
            $formatText += ", Stereo"
        }


        $formatText += ", $($script:recorder.BitsPerSample)-bit PCM"


        $sessionFolder = Split-Path -Parent $script:currentFile

        $message =
            "Recording session saved:`n`n" +
            "$sessionFolder`n`n" +
            "Audio: audio.wav`n" +
            "Format: $formatText`n" +
            "Gain: +$($gainSlider.Value) dB`n" +
            "Size: $sizeKB KB"

        if ($null -ne $script:currentVideoFile -and (Test-Path -LiteralPath $script:currentVideoFile)) {
            $videoInfo = Get-Item -LiteralPath $script:currentVideoFile
            $videoSizeMB = [Math]::Round($videoInfo.Length / 1MB, 1)

            $message +=
                "`n`nVideo: video.avi`n" +
                "Format: $($script:currentVideoMode.Width)x$($script:currentVideoMode.Height), $($script:currentVideoMode.MaxFps) fps, native MJPEG`n" +
                "Size: $videoSizeMB MB"
        }

        $metadataPath = Join-Path $sessionFolder "session.json"

        if (Test-Path -LiteralPath $metadataPath) {
            $message += "`n`nMetadata: session.json"
        }

        if ($null -ne $videoStopError) {
            $message += "`n`nVideo stop warning: $videoStopError"
        }

        [System.Windows.Forms.MessageBox]::Show(
            $message,
            "Nova Recorder",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
        else {

        $statusLabel.Text = "Recording file not found"

        $statusLabel.ForeColor = [System.Drawing.Color]::OrangeRed
    }

    Start-LivePreview
})

# =====================================================================
# Save metadata file
# =====================================================================








# =====================================================================
# Open recordings folder
# =====================================================================

$folderButton.Add_Click({

    Start-Process -FilePath "explorer.exe" -ArgumentList "`"$recordingsDirectory`""
})


# =====================================================================
# Application closing
# =====================================================================

$form.Add_FormClosing({
    $closingArgs = $_
    # DoEvents() runs during camera startup. Never close while the controller
    # is starting or finalizing a capture, or it could dispose live resources.
    if ($script:recordingStarting -or $script:recordingStopping) {
        $closingArgs.Cancel = $true
        [System.Windows.Forms.MessageBox]::Show(
            "NOVA is starting or finalizing a recording. Please finish that operation before closing.",
            "Nova Recorder",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }

    if ($script:recording) {
        # No discard-on-close path: Cancel leaves the recording running.
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "A recording is currently running.`n`nStop, finalize, and save it before closing?`n`nCancel keeps NOVA open and recording.",
            "Nova Recorder",
            [System.Windows.Forms.MessageBoxButtons]::OKCancel,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($answer -ne [System.Windows.Forms.DialogResult]::OK) {
            $closingArgs.Cancel = $true
            return
        }

        $script:recordingStopping = $true
        try {
            $uiTimer.Stop()
            $stopResult = Stop-NovaRecording `
                -AudioDevice $deviceCombo.SelectedItem `
                -GainDb ([double]$gainSlider.Value) `
                -VideoDevice $videoCombo.SelectedItem

            if ($null -ne $stopResult.VideoStopError -or
                $null -ne $stopResult.AudioStopError) {
                throw "Capture shutdown reported an error. Video: $($stopResult.VideoStopError); Audio: $($stopResult.AudioStopError). Raw files may be recoverable."
            }

            # For a video session, a missing MP4 is a finalization failure.
            # Avoid silently closing when muxing did not produce its output.
            if (-not [string]::IsNullOrEmpty($script:currentVideoFile) -and
                (Test-Path -LiteralPath $script:currentVideoFile) -and
                $null -eq $stopResult.CombinedPath) {
                throw "The combined MP4 was not created. Raw WAV and AVI may still be available in $($stopResult.SessionFolder)."
            }
        }
        catch {
            $closingArgs.Cancel = $true
            [System.Windows.Forms.MessageBox]::Show(
                "Recording shutdown needs attention: $($_.Exception.Message)`n`nNOVA will remain open. Check the raw session files before retrying or exiting.",
                "Nova Recorder",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return
        }
        finally {
            $script:recordingStopping = $false
        }
    }

    # When idle, the preview FFmpeg process still owns the webcam.
    # Release it explicitly before the form destroys its PictureBox.
    try {
        Stop-NovaVideoPreview
        Stop-LivePreview
        $uiTimer.Stop()
        $script:recorder.Dispose()
    }
    catch {
        $closingArgs.Cancel = $true
        [System.Windows.Forms.MessageBox]::Show(
            "NOVA could not finish cleaning up recording resources: $($_.Exception.Message)",
            "Nova Recorder",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
})

# =====================================================================
# Nova Combined Mp4
# =====================================================================







# =====================================================================
# Startup
# =====================================================================

Update-DeviceList
Update-VideoDeviceList

$uiTimer.Start()

Start-LivePreview

# =====================================================================
# START audio device-name diagnostics
# =====================================================================

# START UNCOMMENT HERE FOR TROUBLESHOOTING ONLY

#Write-Host ""
#Write-Host "=== NOVA AUDIO DEVICE NAMES ==="

#Get-NovaAudioDeviceNames | ForEach-Object {
#    Write-Host $_
#}

# STOP UNCOMMENT HERE FOR TROUBLESHOOTING ONLY

# =====================================================================
# END audio device-name diagnostics
# =====================================================================

$form.Add_Shown({

    if (
        $videoCheckBox.Checked -and
        $null -ne $videoCombo.SelectedItem -and
        $null -ne $videoModeCombo.SelectedItem
    ) {
        try {
            Start-NovaVideoPreview `
                -DeviceName ([string]$videoCombo.SelectedItem) `
                -Mode $videoModeCombo.SelectedItem `
                -PreviewTarget $previewBox
        }
        catch {
            Write-Host "Camera preview failed: $($_.Exception.Message)"
        }
    }
})

[void]$form.ShowDialog()