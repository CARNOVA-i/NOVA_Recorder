# Device inventory only. Invoked as an isolated PowerShell 5.1 child process.
# Does NOT instantiate NovaWaveRecorder, open media devices, or write to Recordings.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$EngineRoot,
    [Parameter(Mandatory=$true)][string]$OutputJson
)
$ErrorActionPreference = 'Stop'
$inventory = @{ engineRoot=$EngineRoot; ok=$false; microphones=@(); cameras=@(); ffmpeg=$false; error='' }
try {
    $native = Join-Path $EngineRoot 'Engine\NovaNative.ps1'
    $utilities = Join-Path $EngineRoot 'Engine\NovaEngine.ps1'
    foreach ($relative in @('Engine\NovaNative.ps1','Engine\NovaEngine.ps1','Engine\NovaSession.ps1','Engine\NovaVideo.ps1','Engine\NovaController.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $EngineRoot $relative))) {
            throw "Engine component missing: $relative"
        }
    }
    Add-Type -AssemblyName System.Drawing, System.Windows.Forms
    . $native
    . $utilities
    $micDevices = @( [NovaWaveRecorder]::GetDevices() )
    $inventory.microphones = @($micDevices | ForEach-Object { [string]$_.Name })
    $script:ffmpegPath = Join-Path $EngineRoot 'Tools\ffmpeg\ffmpeg.exe'
    $script:ffmpegAvailable = Test-Path -LiteralPath $script:ffmpegPath
    $inventory.ffmpeg = [bool]$script:ffmpegAvailable
    if ($script:ffmpegAvailable) {
        # DirectShow list-only operation: does not open a camera for capture.
        # PS 5.1 can promote FFmpeg's expected stderr enumeration to an error
        # under Stop; temporarily allow stderr while the utility parses it.
        $savedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $inventory.cameras = @(Get-NovaVideoDevices)
        } finally { $ErrorActionPreference = $savedPreference }
    }
    $inventory.ok = $true
} catch {
    $inventory.error = [string]$_.Exception.Message
}
$json = ConvertTo-Json -InputObject $inventory -Depth 4 -Compress
[System.IO.File]::WriteAllText($OutputJson, $json, [System.Text.UTF8Encoding]::new($false))
if (-not $inventory.ok) { exit 1 }
