# WP-02C-I2 | Persistent Microphone Monitoring (experimental)

Source: experimental branch `feature/wp-02c-dynamic-meter` at `1c24af4`, derived from the R1 candidate.
Production `main` remains `821fee1`. No production Engine module is edited by this package.

## Design

- `MIC MONITOR` checked by default, opens the selected WinMM microphone **only after explicit device selection**.
- Native recorder's existing `StartPreview(deviceId)` measures post-gain peaks/clipping without creating an audio file.
- `SET_MONITOR` is serialized over the existing worker bridge. Recording pauses the monitor, uses the same native recorder, and resumes after a successful STOP/finalization.
- Audio-only and A/V use the existing recording controllers and 300 ms sync calibration.
- Monitor failure is reported without treating a successfully finalized session as failed.
- No second microphone process, no camera preview changes, no persistence of microphone selections.
- Spectrum and waveform visuals remain illustrative, not frequency analysis.

## Known limitations and release blockers

- **Experimental**. Windows hardware tests and repeat A/V synchronization assessment are required.
- Intermittent A/V sync anomaly from I1-R1 remains unresolved. Do not merge to main.
- Monitor re-open may be subject to WinMM device driver timing. Report errors before repeated recording.
- Monitor gain uses the slider value at monitor-start; restart monitoring after gain changes if needed.
- Deliberate worker-exit during active recording remains outside the accepted recovery scope.

## Test sequence

1. SCAN ENGINE, CONNECT, select microphone, confirm live peak in READY and no WAV allocated.
2. MIC MONITOR OFF → meter goes idle; ON → live response again.
3. With monitoring active, record WAV, STOP, confirm file and automatic return to monitoring.
4. A/V with and without idle camera preview; check end-to-end MP4 sync and monitor resume.
5. Switch microphone selection while idle, verify one active device and no stale meter; disconnect releases WinMM.
6. Active-recording close protection, reconnect/recovery.

Do not copy to `Studio/Current` or merge before validation.
