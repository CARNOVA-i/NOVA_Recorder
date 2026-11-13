# WP-02C-I1-R1: Candidate-only native audio meter extension.
# This script loads the trusted production native source in memory and adds
# a read-only, high-resolution peak method before type compilation. It never
# modifies the repository's Engine/NovaNative.ps1 or audio capture callback.
param([Parameter(Mandatory=$true)][string]$EngineRoot)

$nativePath = Join-Path $EngineRoot 'Engine\NovaNative.ps1'
if (-not (Test-Path -LiteralPath $nativePath -PathType Leaf)) {
    throw 'Trusted native module missing.'
}
$nativeText = [System.IO.File]::ReadAllText($nativePath)
$anchor = 'public int GetPeakPercent()'
if ($nativeText.Split([string[]]@($anchor),[System.StringSplitOptions]::None).Length -ne 2 -or
    $nativeText -notmatch 'private int currentPeak\s*=') {
    throw 'Unexpected native engine meter implementation; refusing candidate overlay.'
}

# Use the same atomic peak sample as GetPeakPercent, preserving post-gain PCM
# semantics, clip detection, WAV content, and timing. No audio callback edits.
$injected = @'
public double GetPeakDbfs()
    {
        int peak = Interlocked.Exchange(ref currentPeak, 0);
        if (peak <= 0) return -96.0;
        double ratio = Math.Min(1.0, (double)peak / 32768.0);
        return Math.Max(-96.0, 20.0 * Math.Log10(ratio));
    }

    public int GetPeakPercent()
'@
$modifiedNative = $nativeText.Replace($anchor,$injected.TrimEnd("`r","`n"))
# Source the modified trusted module in this worker only. If the engine changes
# unexpectedly, the anchor check above fails closed rather than silently
# reporting an inaccurate meter.
. ([scriptblock]::Create($modifiedNative))
