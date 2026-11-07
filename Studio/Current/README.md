# NOVA Studio | WP-02B2B-I3B-I1-R2 - Camera preflight state correction

## Evidence and root cause
R1's A/V startup sets the worker state to `STARTING`, then invokes automatic camera preflight. The preflight called `Start-StudioCameraPreview`, which rejected any state other than `READY`, producing `Preview requires idle audio recorder.` This is a verified state-ordering conflict, not evidence of FFmpeg or camera failure.

## Changes (prototype only)
- `Bridge/Start-NovaControllerHost.ps1`: internal A/V preflight may start preview while state is `STARTING`, **only** when explicitly requested from the preflight call and native audio/video are idle. Ordinary user `START_PREVIEW` commands remain READY-only. The existing first JPEG gate, camera release, 3 s handoff, recording FFmpeg, audio start, 300 ms final mux offset, and cleanup remain unchanged.
- `Launch-NovaStudio.ps1`: when an error leaves the worker in `ERROR` and confirms no audio, video, preview, or pending command, the **DISCONNECT** control is enabled to allow orderly recovery instead of trapping the window. Disconnect itself retains its independent capture safety checks.
- No production engine modifications, commits or pushes. Existing accepted build I3A-I2 remains rollback.

## Recover from existing R1 ERROR session
The currently running R1 cockpit does not expose DISCONNECT in ERROR. Do not force-close an uncertain recording. Capture state data and check `audioCaptureStarted=false`, `videoCaptureStarted=false`, `previewActive=false`, and no session folder first. The new R2 build provides safe disconnect on future idle ERROR states. A manual worker DISCONNECT for the old R1 session is described in conversation, with checks before sending it.

## Launch R2 (new extracted folder)
```powershell
cd 'U:\Celliott\Carson\NOVA_Studio_WP02B2B_I3B_I1_R2'
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File '.\Launch-NovaStudio.ps1'
```
`-NoProfile`: skips profiles. `-STA`: WPF apartment. `-ExecutionPolicy Bypass`: child-process scoped. `-File`: specifies launcher.

## Minimal Windows acceptance (with flight notes)
1. Cold start: Connect; choose mic/camera/MJPEG mode; **do not start preview**; enable A/V and RECORD. Verify first frame, then RECORDING.
2. STOP after short disposable recording; verify WAV + AVI + JSON + playable synchronized MP4.
3. Repeat A/V with manual preview already running. Verify preview handoff and MP4.
4. WAV-only regression: record after preview stop; verify playback and JSON.
5. Error recovery only if an error naturally occurs: when status confirms no capture, DISCONNECT must be available and complete; never deliberately inject recording failures into a valuable session.
6. STOP PREVIEW, DISCONNECT, reconnect, and close. Confirm no left-behind FFmpeg process attributable to Studio.

Record any frame-rate metrics and observations in a **Notes** field. Stop after the first unexpected error and preserve diagnostics.

## Verification
Static structure, UTF-8 BOM and XAML parsing checked. Windows PowerShell, camera and FFmpeg execution remain untested in this environment. **CHANGES REQUIRED until Windows tests pass.**
