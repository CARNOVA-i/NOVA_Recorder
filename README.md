# Nova Recorder

Nova Recorder is a lightweight, portable Windows audio recorder built with PowerShell and the native Windows multimedia API.

It was designed to run on a Windows workstation without requiring installation, external libraries, Python, package managers, or administrator access.

## Features

- Explicit microphone selection
- Native Windows audio capture using `winmm.dll`
- Live post-gain input level meter
- Adjustable software gain
- Default gain of `+16 dB`
- Gain range from `0 dB` to `+32 dB`
- Clipping indicator
- 16-bit PCM WAV recording
- Automatic timestamped filenames
- Automatic `Recordings` folder creation
- Open Recordings Folder button
- Portable PowerShell script
- No external dependencies

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell
- A working recording device or microphone
- Permission for desktop applications to access the microphone

No installation is required.


## Command Explanation

Run Nova Recorder with:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\nova_recorder.ps1"
```

`powershell.exe`  
Starts Windows PowerShell.

`-ExecutionPolicy Bypass`  
Allows the unsigned local script to run for that PowerShell process only. It does not permanently change the computer's execution policy.

`-File`  
Tells PowerShell to execute the specified script.

`.\nova_recorder.ps1`  
Runs `nova_recorder.ps1` from the current directory.

## Using the Recorder

1. Launch Nova Recorder.
2. Select the desired microphone from the **Microphone** dropdown.
3. Adjust **Recording gain** if required.
4. Press **RECORD**.
5. Watch the live input-level meter while speaking.
6. Watch the **CLIP** indicator for excessive input level.
7. Press **STOP** when finished.
8. The WAV file is saved automatically in the `Recordings` folder.

## Recording Gain

Nova Recorder applies digital gain directly to the captured PCM audio before it is written to disk.

The current gain range is:

```text
0 dB ───── +8 dB ───── +16 dB ───── +24 dB ───── +32 dB
                         ^
                       default
```

The default is `+16 dB`.

This value was selected because it produced a useful recording level with the original target microphone.

### Approximate Gain Multipliers

| Gain | Approximate Amplitude |
|---:|---:|
| 0 dB | 1.00x |
| +6 dB | 2.00x |
| +8 dB | 2.51x |
| +12 dB | 3.98x |
| +16 dB | 6.31x |
| +24 dB | 15.85x |
| +32 dB | 39.81x |

Digital gain amplifies both the desired signal and any noise already present in the microphone signal.

It does not improve the physical signal-to-noise ratio of the microphone or audio interface.

## Input Meter

The input meter displays the approximate peak level of the audio after Nova Recorder's digital gain has been applied.

A useful target for normal speech is approximately:

```text
50% to 80%
```

There is no need to make normal speech reach 100%.

Leaving some headroom prevents clipping during louder words or unexpected sounds.

## CLIP Indicator

The `CLIP` indicator turns red when amplification would push a PCM sample beyond the maximum representable 16-bit value.

Nova Recorder prevents integer overflow by clamping the sample to the valid PCM range.

If `CLIP` flashes frequently during normal speech, reduce the recording gain.

Occasional clipping during an unusually loud sound is less concerning, but sustained clipping will produce audible distortion.

## Audio Format

Nova Recorder records uncompressed PCM WAV audio.

The recorder attempts the following capture formats in order:

1. 48,000 Hz, mono, 16-bit
2. 44,100 Hz, mono, 16-bit
3. 48,000 Hz, stereo, 16-bit
4. 44,100 Hz, stereo, 16-bit

Mono is preferred because Nova Recorder is primarily intended for voice recording.

The actual format used is displayed after the recording is saved.

## Windows Microphone Format

For the original test system, the Windows microphone device was configured as:

```text
2 channels
16 bit
48,000 Hz
```

Nova Recorder does not require this exact Windows setting, but `16-bit / 48 kHz` provides a clean and predictable configuration for testing.

## Output Files

Recordings are saved using timestamped filenames:

```text
Recording_YYYY-MM-DD_HH-mm-ss.wav
```

Example:

```text
Recording_2026-08-07_10-42-18.wav
```

This prevents normal recordings from overwriting each other.

## Technical Overview

Nova Recorder consists of two main layers.

### PowerShell / Windows Forms

PowerShell provides:

- the graphical interface
- microphone selection
- buttons
- gain slider
- status display
- recording timer
- file management

### Native C# Audio Engine

A small C# audio engine is compiled at runtime using PowerShell's `Add-Type`.

The engine communicates directly with the native Windows `winmm.dll` API.

The main Windows audio functions include:

```text
waveInGetNumDevs
waveInGetDevCaps
waveInOpen
waveInPrepareHeader
waveInAddBuffer
waveInStart
waveInStop
waveInReset
waveInClose
```

Audio is captured into native buffers, converted to managed byte arrays, amplified if required, and written directly to a PCM WAV file.


## Folder Structure

Nova Recorder can be stored in any writable folder.

Example:

```text
NOVA_Recorder/
├── nova_recorder.ps1
├── README.md
└── Recordings/# NOVA_Recorder
```


## License

Nova Recorder is released under the [MIT License](LICENSE).