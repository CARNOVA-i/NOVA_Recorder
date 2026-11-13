# NOVA Studio WP-02C-I1-R1: Dynamic Meter (isolated Windows test candidate)

Based on the hardware-validated WP-02C-I1 candidate and accepted R3 controller (`821fee1`). **No Git changes or production engine edits.**

## Change summary
- Worker extends the *trusted native C# source in memory* before type compilation with `GetPeakDbfs()`. This consumes the original post-gain peak via atomic exchange, retaining native capture, WAV, and clipping behavior. The production `Engine/NovaNative.ps1` is never overwritten.
- Publishes double-precision post-gain peak dBFS at ~10 Hz instead of integer percent at ~5 Hz. A silent interval returns -96 dBFS (display floor -60 dBFS).
- UI gauge adds 35 ms attack, 340 ms release, and 480 ms peak hold, based on elapsed time. Displays segmented level movement and real level-driven head glow.
- Spectrum/waveform remain **illustrative**, NOT an FFT or raw PCM waveform. dBFS is sample peak, **not RMS or calibrated SPL**.
- Meter active **only while recording**. Camera/video control, audio startup, AVI/WAV/MP4 finalization and 300 ms sync calibration unchanged.

## Engineering tradeoff
The native source extension uses a guarded text anchor (`public int GetPeakPercent()`) inside the trusted local source and compiles the modified script in the isolated worker. It fails on incompatible module signatures instead of modifying the production file. Before adoption, integrate this getter cleanly into a governed engine revision rather than retaining the runtime source overlay long-term.

## Quick hardware validation
1. Connect, record WAV, confirm dynamic changes across whisper/normal/loud speech, silence decay and peak hold.
2. Confirm clipping only on actual overload and that gain changes impact peak reading, without distortion in normal speech.
3. Record and finalize an A/V session, play MP4 and inspect clap sync.
4. Verify stop/restart, disconnect/reconnect, protected close and idle worker-exit recovery.
5. If engine initialization fails, preserve bridge error and original package. Do not edit production Engine files.
