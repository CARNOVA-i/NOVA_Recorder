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


# =====================================================================
# Native audio engine
# =====================================================================

$novaSource = @"
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;


public class NovaAudioDevice
{
    public int Id { get; set; }

    public string Name { get; set; }

    public override string ToString()
    {
        return Name;
    }
}

public class CyberHeadMeter : Control
{
    private int level = 0;
    private bool clipping = false;

    public int Level
    {
        get { return level; }

        set
        {
            int newValue = value;

            if (newValue < 0)
                newValue = 0;

            if (newValue > 100)
                newValue = 100;

            level = newValue;

            Invalidate();
        }
    }


    public bool Clipping
    {
        get { return clipping; }

        set
        {
            clipping = value;

            Invalidate();
        }
    }


    public CyberHeadMeter()
    {
        SetStyle(
            ControlStyles.AllPaintingInWmPaint |
            ControlStyles.UserPaint |
            ControlStyles.OptimizedDoubleBuffer |
            ControlStyles.ResizeRedraw,
            true
        );

        BackColor =
            Color.FromArgb(
                28,
                30,
                34
            );
    }


    protected override void OnPaint(
        PaintEventArgs e
    )
    {
        base.OnPaint(e);

        Graphics g = e.Graphics;

        g.SmoothingMode =
            SmoothingMode.AntiAlias;

        g.Clear(BackColor);


        RectangleF bounds =
            new RectangleF(
                8,
                14,
                Width - 16,
                Height - 32
            );


        using (
            GraphicsPath head =
                CreateHeadPath(bounds)
        )
        {
            // ---------------------------------------------------------
            // Dark interior
            // ---------------------------------------------------------

            using (
                SolidBrush interior =
                    new SolidBrush(
                        Color.FromArgb(
                            20,
                            21,
                            27
                        )
                    )
            )
            {
                g.FillPath(
                    interior,
                    head
                );
            }


            // ---------------------------------------------------------
            // Bottom-up purple audio fill
            // ---------------------------------------------------------

            float normalized =
                level / 100f;

            float fillHeight =
                bounds.Height *
                normalized;

            RectangleF fillRectangle =
                new RectangleF(
                    bounds.Left,
                    bounds.Bottom - fillHeight,
                    bounds.Width,
                    fillHeight
                );


            GraphicsState state =
                g.Save();

            g.SetClip(
                head
            );


            if (fillHeight > 0)
            {
                using (
                    LinearGradientBrush fill =
                        new LinearGradientBrush(
                            fillRectangle,
                            Color.FromArgb(
                                120,
                                48,
                                0,
                                150
                            ),
                            Color.FromArgb(
                                235,
                                200,
                                80,
                                255
                            ),
                            LinearGradientMode.Vertical
                        )
                )
                {
                    g.FillRectangle(
                        fill,
                        fillRectangle
                    );
                }


                // Bright surface line at current audio level.

                using (
                    Pen surface =
                        new Pen(
                            Color.FromArgb(
                                230,
                                220,
                                145,
                                255
                            ),
                            2f
                        )
                )
                {
                    float y =
                        bounds.Bottom -
                        fillHeight;

                    g.DrawLine(
                        surface,
                        bounds.Left,
                        y,
                        bounds.Right,
                        y
                    );
                }
            }


            g.Restore(
                state
            );


            // ---------------------------------------------------------
            // Cyberpunk internal details
            // ---------------------------------------------------------

            using (
                Pen detail =
                    new Pen(
                        Color.FromArgb(
                            110,
                            175,
                            95,
                            230
                        ),
                        1.2f
                    )
            )
            {
                detail.DashStyle =
                    DashStyle.Dot;


                float centerX =
                    bounds.Left +
                    bounds.Width * 0.5f;


                g.DrawLine(
                    detail,
                    centerX,
                    bounds.Top + bounds.Height * 0.20f,
                    centerX,
                    bounds.Top + bounds.Height * 0.72f
                );


                g.DrawLine(
                    detail,
                    bounds.Left + bounds.Width * 0.26f,
                    bounds.Top + bounds.Height * 0.44f,
                    bounds.Right - bounds.Width * 0.26f,
                    bounds.Top + bounds.Height * 0.44f
                );


                g.DrawLine(
                    detail,
                    bounds.Left + bounds.Width * 0.31f,
                    bounds.Top + bounds.Height * 0.58f,
                    bounds.Right - bounds.Width * 0.31f,
                    bounds.Top + bounds.Height * 0.58f
                );
            }


            // ---------------------------------------------------------
            // Main neon outline
            // ---------------------------------------------------------

            Color outlineColor =
                clipping
                ? Color.FromArgb(
                    255,
                    245,
                    65,
                    90
                )
                : Color.FromArgb(
                    235,
                    190,
                    105,
                    255
                );


            // Soft outer glow.

            using (
                Pen glow =
                    new Pen(
                        Color.FromArgb(
                            65,
                            outlineColor
                        ),
                        7f
                    )
            )
            {
                g.DrawPath(
                    glow,
                    head
                );
            }


            using (
                Pen outline =
                    new Pen(
                        outlineColor,
                        2.2f
                    )
            )
            {
                g.DrawPath(
                    outline,
                    head
                );
            }


           // ---------------------------------------------------------
            // Integrated cyber visor
            // ---------------------------------------------------------

            Color visorColor =
                clipping
                ? Color.FromArgb(
                    255,
                    255,
                    90,
                    105
                )
                : Color.FromArgb(
                    255,
                    225,
                    155,
                    255
                );

            using (
                Pen visorGlow =
                    new Pen(
                        Color.FromArgb(
                            70,
                            visorColor
                        ),
                        6f
                    )
            )
            {
                float y =
                    bounds.Top +
                    bounds.Height * 0.37f;

                float left =
                    bounds.Left +
                    bounds.Width * 0.22f;

                float right =
                    bounds.Right -
                    bounds.Width * 0.22f;

                float center =
                    bounds.Left +
                    bounds.Width * 0.5f;

                g.DrawLine(
                    visorGlow,
                    left,
                    y,
                    center - bounds.Width * 0.06f,
                    y + 4
                );

                g.DrawLine(
                    visorGlow,
                    center - bounds.Width * 0.06f,
                    y + 4,
                    center,
                    y + 1
                );

                g.DrawLine(
                    visorGlow,
                    center,
                    y + 1,
                    center + bounds.Width * 0.06f,
                    y + 4
                );

                g.DrawLine(
                    visorGlow,
                    center + bounds.Width * 0.06f,
                    y + 4,
                    right,
                    y
                );
            }


            using (
                Pen visor =
                    new Pen(
                        visorColor,
                        2.4f
                    )
            )
            {
                float y =
                    bounds.Top +
                    bounds.Height * 0.37f;

                float left =
                    bounds.Left +
                    bounds.Width * 0.22f;

                float right =
                    bounds.Right -
                    bounds.Width * 0.22f;

                float center =
                    bounds.Left +
                    bounds.Width * 0.5f;

                g.DrawLine(
                    visor,
                    left,
                    y,
                    center - bounds.Width * 0.06f,
                    y + 4
                );

                g.DrawLine(
                    visor,
                    center - bounds.Width * 0.06f,
                    y + 4,
                    center,
                    y + 1
                );

                g.DrawLine(
                    visor,
                    center,
                    y + 1,
                    center + bounds.Width * 0.06f,
                    y + 4
                );

                g.DrawLine(
                    visor,
                    center + bounds.Width * 0.06f,
                    y + 4,
                    right,
                    y
                );
            }
        }
    }


    private GraphicsPath CreateHeadPath(
    RectangleF r
)
{
    GraphicsPath path =
        new GraphicsPath();

    float cx =
        r.Left +
        r.Width * 0.5f;

    float top =
        r.Top;

    float bottom =
        r.Bottom;

    path.StartFigure();

    // -------------------------------------------------------------
    // Top crown / sensor nub
    // -------------------------------------------------------------

    path.AddLine(
        cx,
        top,

        r.Left + r.Width * 0.44f,
        top
    );

    path.AddLine(
        r.Left + r.Width * 0.44f,
        top,

        r.Left + r.Width * 0.44f,
        r.Top + r.Height * 0.07f
    );

    path.AddLine(
        r.Left + r.Width * 0.44f,
        r.Top + r.Height * 0.07f,

        r.Left + r.Width * 0.35f,
        r.Top + r.Height * 0.07f
    );

    // -------------------------------------------------------------
    // Left dome / forehead
    // -------------------------------------------------------------

    path.AddBezier(
        r.Left + r.Width * 0.35f,
        r.Top + r.Height * 0.07f,

        r.Left + r.Width * 0.24f,
        r.Top + r.Height * 0.10f,

        r.Left + r.Width * 0.18f,
        r.Top + r.Height * 0.17f,

        r.Left + r.Width * 0.14f,
        r.Top + r.Height * 0.25f
    );

    // -------------------------------------------------------------
    // Left temple wall
    // -------------------------------------------------------------

    path.AddLine(
        r.Left + r.Width * 0.14f,
        r.Top + r.Height * 0.25f,

        r.Left + r.Width * 0.14f,
        r.Top + r.Height * 0.38f
    );

    // -------------------------------------------------------------
    // Left temple flare
    // -------------------------------------------------------------

    path.AddLine(
        r.Left + r.Width * 0.14f,
        r.Top + r.Height * 0.38f,

        r.Left + r.Width * 0.07f,
        r.Top + r.Height * 0.42f
    );

    path.AddLine(
        r.Left + r.Width * 0.07f,
        r.Top + r.Height * 0.42f,

        r.Left + r.Width * 0.14f,
        r.Top + r.Height * 0.56f
    );

    // -------------------------------------------------------------
    // Left lower cheek / side wall
    // -------------------------------------------------------------

    path.AddLine(
        r.Left + r.Width * 0.14f,
        r.Top + r.Height * 0.56f,

        r.Left + r.Width * 0.14f,
        r.Top + r.Height * 0.67f
    );

    // -------------------------------------------------------------
    // Left cheek pod
    // -------------------------------------------------------------

    path.AddBezier(
        r.Left + r.Width * 0.14f,
        r.Top + r.Height * 0.67f,

        r.Left + r.Width * 0.09f,
        r.Top + r.Height * 0.75f,

        r.Left + r.Width * 0.10f,
        r.Top + r.Height * 0.88f,

        r.Left + r.Width * 0.22f,
        r.Top + r.Height * 0.88f
    );

    path.AddBezier(
        r.Left + r.Width * 0.22f,
        r.Top + r.Height * 0.88f,

        r.Left + r.Width * 0.28f,
        r.Top + r.Height * 0.88f,

        r.Left + r.Width * 0.31f,
        r.Top + r.Height * 0.82f,

        r.Left + r.Width * 0.34f,
        r.Top + r.Height * 0.79f
    );

    // -------------------------------------------------------------
    // Left jaw / chin approach
    // -------------------------------------------------------------

    path.AddLine(
        r.Left + r.Width * 0.34f,
        r.Top + r.Height * 0.79f,

        r.Left + r.Width * 0.39f,
        r.Top + r.Height * 0.90f
    );

    path.AddLine(
        r.Left + r.Width * 0.39f,
        r.Top + r.Height * 0.90f,

        r.Left + r.Width * 0.46f,
        r.Top + r.Height * 0.94f
    );

    // -------------------------------------------------------------
    // Center chin point
    // -------------------------------------------------------------

    path.AddLine(
        r.Left + r.Width * 0.46f,
        r.Top + r.Height * 0.94f,

        cx,
        bottom
    );

    path.AddLine(
        cx,
        bottom,

        r.Right - r.Width * 0.46f,
        r.Top + r.Height * 0.94f
    );

    // -------------------------------------------------------------
    // Right jaw / chin approach
    // -------------------------------------------------------------

    path.AddLine(
        r.Right - r.Width * 0.46f,
        r.Top + r.Height * 0.94f,

        r.Right - r.Width * 0.39f,
        r.Top + r.Height * 0.90f
    );

    path.AddLine(
        r.Right - r.Width * 0.39f,
        r.Top + r.Height * 0.90f,

        r.Right - r.Width * 0.34f,
        r.Top + r.Height * 0.79f
    );

    // -------------------------------------------------------------
    // Right cheek pod
    // -------------------------------------------------------------

    path.AddBezier(
        r.Right - r.Width * 0.34f,
        r.Top + r.Height * 0.79f,

        r.Right - r.Width * 0.31f,
        r.Top + r.Height * 0.82f,

        r.Right - r.Width * 0.28f,
        r.Top + r.Height * 0.88f,

        r.Right - r.Width * 0.22f,
        r.Top + r.Height * 0.88f
    );

    path.AddBezier(
        r.Right - r.Width * 0.22f,
        r.Top + r.Height * 0.88f,

        r.Right - r.Width * 0.10f,
        r.Top + r.Height * 0.88f,

        r.Right - r.Width * 0.09f,
        r.Top + r.Height * 0.75f,

        r.Right - r.Width * 0.14f,
        r.Top + r.Height * 0.67f
    );

    // -------------------------------------------------------------
    // Right lower cheek / side wall
    // -------------------------------------------------------------

    path.AddLine(
        r.Right - r.Width * 0.14f,
        r.Top + r.Height * 0.67f,

        r.Right - r.Width * 0.14f,
        r.Top + r.Height * 0.56f
    );

    // -------------------------------------------------------------
    // Right temple flare
    // -------------------------------------------------------------

    path.AddLine(
        r.Right - r.Width * 0.14f,
        r.Top + r.Height * 0.56f,

        r.Right - r.Width * 0.07f,
        r.Top + r.Height * 0.42f
    );

    path.AddLine(
        r.Right - r.Width * 0.07f,
        r.Top + r.Height * 0.42f,

        r.Right - r.Width * 0.14f,
        r.Top + r.Height * 0.38f
    );

    // -------------------------------------------------------------
    // Right temple wall
    // -------------------------------------------------------------

    path.AddLine(
        r.Right - r.Width * 0.14f,
        r.Top + r.Height * 0.38f,

        r.Right - r.Width * 0.14f,
        r.Top + r.Height * 0.25f
    );

    // -------------------------------------------------------------
    // Right dome / forehead
    // -------------------------------------------------------------

    path.AddBezier(
        r.Right - r.Width * 0.14f,
        r.Top + r.Height * 0.25f,

        r.Right - r.Width * 0.18f,
        r.Top + r.Height * 0.17f,

        r.Right - r.Width * 0.24f,
        r.Top + r.Height * 0.10f,

        r.Right - r.Width * 0.35f,
        r.Top + r.Height * 0.07f
    );

    path.AddLine(
        r.Right - r.Width * 0.35f,
        r.Top + r.Height * 0.07f,

        r.Right - r.Width * 0.44f,
        r.Top + r.Height * 0.07f
    );

    path.AddLine(
        r.Right - r.Width * 0.44f,
        r.Top + r.Height * 0.07f,

        r.Right - r.Width * 0.44f,
        top
    );

    path.AddLine(
        r.Right - r.Width * 0.44f,
        top,

        cx,
        top
    );

    path.CloseFigure();

    return path;
}
}

public class NovaWaveRecorder : IDisposable
{
    // -----------------------------------------------------------------
    // WinMM constants
    // -----------------------------------------------------------------

    private const int CALLBACK_FUNCTION = 0x00030000;

    private const int WIM_OPEN  = 0x03BE;
    private const int WIM_CLOSE = 0x03BF;
    private const int WIM_DATA  = 0x03C0;

    private const int MMSYSERR_NOERROR = 0;
    private const int WAVERR_STILLPLAYING = 33;

    private const int WAVE_FORMAT_PCM = 1;


    // -----------------------------------------------------------------
    // Native structures
    // -----------------------------------------------------------------

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct WAVEINCAPS
    {
        public ushort wMid;
        public ushort wPid;
        public uint vDriverVersion;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szPname;

        public uint dwFormats;
        public ushort wChannels;
        public ushort wReserved1;
    }


    [StructLayout(LayoutKind.Sequential)]
    private struct WAVEFORMATEX
    {
        public ushort wFormatTag;
        public ushort nChannels;
        public uint nSamplesPerSec;
        public uint nAvgBytesPerSec;
        public ushort nBlockAlign;
        public ushort wBitsPerSample;
        public ushort cbSize;
    }


    [StructLayout(LayoutKind.Sequential)]
    private struct WAVEHDR
    {
        public IntPtr lpData;
        public uint dwBufferLength;
        public uint dwBytesRecorded;
        public IntPtr dwUser;
        public uint dwFlags;
        public uint dwLoops;
        public IntPtr lpNext;
        public IntPtr reserved;
    }


    private class AudioBuffer
    {
        public IntPtr DataPointer;
        public IntPtr HeaderPointer;
        public int Length;
    }


    // -----------------------------------------------------------------
    // Native function declarations
    // -----------------------------------------------------------------

    private delegate void WaveInCallback(
        IntPtr hwi,
        uint message,
        IntPtr instance,
        IntPtr param1,
        IntPtr param2
    );


    [DllImport("winmm.dll")]
    private static extern uint waveInGetNumDevs();


    [DllImport("winmm.dll", CharSet = CharSet.Auto)]
    private static extern int waveInGetDevCaps(
        UIntPtr deviceId,
        out WAVEINCAPS caps,
        uint capsSize
    );


    [DllImport("winmm.dll")]
    private static extern int waveInOpen(
        out IntPtr waveInHandle,
        uint deviceId,
        ref WAVEFORMATEX format,
        WaveInCallback callback,
        IntPtr instance,
        int flags
    );


    [DllImport("winmm.dll")]
    private static extern int waveInPrepareHeader(
        IntPtr waveInHandle,
        IntPtr header,
        uint headerSize
    );


    [DllImport("winmm.dll")]
    private static extern int waveInUnprepareHeader(
        IntPtr waveInHandle,
        IntPtr header,
        uint headerSize
    );


    [DllImport("winmm.dll")]
    private static extern int waveInAddBuffer(
        IntPtr waveInHandle,
        IntPtr header,
        uint headerSize
    );


    [DllImport("winmm.dll")]
    private static extern int waveInStart(
        IntPtr waveInHandle
    );


    [DllImport("winmm.dll")]
    private static extern int waveInStop(
        IntPtr waveInHandle
    );


    [DllImport("winmm.dll")]
    private static extern int waveInReset(
        IntPtr waveInHandle
    );


    [DllImport("winmm.dll")]
    private static extern int waveInClose(
        IntPtr waveInHandle
    );


    [DllImport("winmm.dll", CharSet = CharSet.Auto)]
    private static extern int waveInGetErrorText(
        int errorCode,
        StringBuilder errorText,
        int errorTextSize
    );


    // -----------------------------------------------------------------
    // Recorder state
    // -----------------------------------------------------------------

    private IntPtr waveHandle = IntPtr.Zero;

    private WaveInCallback callbackDelegate;

    private readonly List<AudioBuffer> buffers =
        new List<AudioBuffer>();

    private readonly object sync =
        new object();

    private BinaryWriter writer;

    private volatile bool recording = false;

    private volatile bool previewing = false;

    private int currentPeak = 0;

    private int clippingFlag = 0;

    private long dataBytesWritten = 0;

    private int sampleRate = 48000;

    private int channels = 1;

    private int bitsPerSample = 16;

    private string currentFile = null;

    private double gainDb = 16.0;

    private double gainMultiplier =
        Math.Pow(10.0, 16.0 / 20.0);


    // -----------------------------------------------------------------
    // Public properties
    // -----------------------------------------------------------------

    public bool IsRecording
    {
        get { return recording; }
    }

    public bool IsPreviewing
    {
        get { return previewing; }
    }

    public int SampleRate
    {
        get { return sampleRate; }
    }


    public int Channels
    {
        get { return channels; }
    }


    public int BitsPerSample
    {
        get { return bitsPerSample; }
    }


    public string CurrentFile
    {
        get { return currentFile; }
    }


    // -----------------------------------------------------------------
    // Gain control
    // -----------------------------------------------------------------

    public void SetGainDb(double db)
    {
        if (db < 0.0)
        {
            db = 0.0;
        }

        if (db > 32.0)
        {
            db = 32.0;
        }

        gainDb = db;

        gainMultiplier =
            Math.Pow(
                10.0,
                db / 20.0
            );
    }


    public double GetGainDb()
    {
        return gainDb;
    }


    // -----------------------------------------------------------------
    // Device enumeration
    // -----------------------------------------------------------------

    public static List<NovaAudioDevice> GetDevices()
    {
        List<NovaAudioDevice> devices =
            new List<NovaAudioDevice>();

        uint count =
            waveInGetNumDevs();

        for (uint i = 0; i < count; i++)
        {
            WAVEINCAPS caps;

            int result =
                waveInGetDevCaps(
                    new UIntPtr(i),
                    out caps,
                    (uint)Marshal.SizeOf(
                        typeof(WAVEINCAPS)
                    )
                );

            if (result == MMSYSERR_NOERROR)
            {
                NovaAudioDevice device =
                    new NovaAudioDevice();

                device.Id = (int)i;

                device.Name =
                    caps.szPname;

                devices.Add(device);
            }
        }

        return devices;
    }


    // -----------------------------------------------------------------
    // Error handling
    // -----------------------------------------------------------------

    private static string GetErrorText(int code)
    {
        StringBuilder text =
            new StringBuilder(256);

        int result =
            waveInGetErrorText(
                code,
                text,
                text.Capacity
            );

        if (result == MMSYSERR_NOERROR)
        {
            return text.ToString();
        }

        return "Unknown Windows audio error.";
    }


    private static void ThrowIfError(
        int result,
        string operation
    )
    {
        if (result != MMSYSERR_NOERROR)
        {
            throw new Exception(
                operation +
                " failed." +
                Environment.NewLine +
                Environment.NewLine +
                "Windows audio error " +
                result +
                ": " +
                GetErrorText(result)
            );
        }
    }


    // -----------------------------------------------------------------
    // Create PCM format
    // -----------------------------------------------------------------

    private WAVEFORMATEX CreateFormat(
        int rate,
        int channelCount
    )
    {
        WAVEFORMATEX format =
            new WAVEFORMATEX();

        format.wFormatTag =
            WAVE_FORMAT_PCM;

        format.nChannels =
            (ushort)channelCount;

        format.nSamplesPerSec =
            (uint)rate;

        format.wBitsPerSample =
            (ushort)bitsPerSample;

        format.nBlockAlign =
            (ushort)(
                channelCount *
                bitsPerSample /
                8
            );

        format.nAvgBytesPerSec =
            format.nSamplesPerSec *
            format.nBlockAlign;

        format.cbSize = 0;

        return format;
    }



    private void OpenCapture(int deviceId)
    {
        callbackDelegate = new WaveInCallback(AudioCallback);

        currentPeak = 0;

        Interlocked.Exchange(
            ref clippingFlag,
            0
        );

        int[,] formats =
        {
            { 48000, 1 },
            { 44100, 1 },
            { 48000, 2 },
            { 44100, 2 }
        };

        int lastError = -1;
        bool opened = false;

        for (
            int i = 0;
            i < formats.GetLength(0);
            i++
        )
        {
            int tryRate =
                formats[i, 0];

            int tryChannels =
                formats[i, 1];

            WAVEFORMATEX format =
                CreateFormat(
                    tryRate,
                    tryChannels
                );

            IntPtr handle;

            int result =
                waveInOpen(
                    out handle,
                    (uint)deviceId,
                    ref format,
                    callbackDelegate,
                    IntPtr.Zero,
                    CALLBACK_FUNCTION
                );

            if (result == MMSYSERR_NOERROR)
            {
                waveHandle =
                    handle;

                sampleRate =
                    tryRate;

                channels =
                    tryChannels;

                opened =
                    true;

                break;
            }

            lastError =
                result;
        }

        if (!opened)
        {
            throw new Exception(
                "Could not open the selected microphone." +
                Environment.NewLine +
                Environment.NewLine +
                "Windows audio error " +
                lastError +
                ": " +
                GetErrorText(lastError)
            );
        }

        CreateBuffers();

        int startResult =
            waveInStart(
                waveHandle
            );

        ThrowIfError(
            startResult,
            "Starting microphone capture"
        );
    }



    public void StartPreview(int deviceId)
    {
        if (recording || previewing)
        {
            return;
        }

        writer = null;
        currentFile = null;
        dataBytesWritten = 0;

        previewing = true;

        try
        {
            OpenCapture(deviceId);
        }
        catch
        {
            previewing = false;

            CleanupAudio();

            throw;
        }
    }


    public void StopPreview()
    {
        if (!previewing)
        {
            return;
        }

        previewing = false;

        if (waveHandle != IntPtr.Zero)
        {
            waveInStop(waveHandle);
            waveInReset(waveHandle);

            Thread.Sleep(100);
        }

        lock (sync)
        {
            CleanupAudio();
        }

        currentPeak = 0;

        Interlocked.Exchange(
            ref clippingFlag,
            0
        );
    }


    // -----------------------------------------------------------------
    // Start recording
    // -----------------------------------------------------------------

    public void Start(
        int deviceId,
        string filePath
    )
    {
        if (recording)
        {
            throw new InvalidOperationException(
                "The recorder is already running."
            );
        }

        if (previewing)
        {
            StopPreview();
        }

        callbackDelegate =
            new WaveInCallback(AudioCallback);

        currentFile =
            filePath;

        dataBytesWritten =
            0;

        currentPeak =
            0;

        Interlocked.Exchange(
            ref clippingFlag,
            0
        );


        // Try common PCM capture formats.
        //
        // Mono is preferred because this is primarily a
        // voice recorder.
        int[,] formats =
        {
            { 48000, 1 },
            { 44100, 1 },
            { 48000, 2 },
            { 44100, 2 }
        };


        int lastError = -1;

        bool opened = false;


        for (
            int i = 0;
            i < formats.GetLength(0);
            i++
        )
        {
            int tryRate =
                formats[i, 0];

            int tryChannels =
                formats[i, 1];

            WAVEFORMATEX format =
                CreateFormat(
                    tryRate,
                    tryChannels
                );

            IntPtr handle;

            int result =
                waveInOpen(
                    out handle,
                    (uint)deviceId,
                    ref format,
                    callbackDelegate,
                    IntPtr.Zero,
                    CALLBACK_FUNCTION
                );


            if (result == MMSYSERR_NOERROR)
            {
                waveHandle =
                    handle;

                sampleRate =
                    tryRate;

                channels =
                    tryChannels;

                opened =
                    true;

                break;
            }

            lastError =
                result;
        }


        if (!opened)
        {
            throw new Exception(
                "Could not open the selected microphone." +
                Environment.NewLine +
                Environment.NewLine +
                "Windows audio error " +
                lastError +
                ": " +
                GetErrorText(lastError)
            );
        }


        try
        {
            writer =
                new BinaryWriter(
                    new FileStream(
                        filePath,
                        FileMode.Create,
                        FileAccess.Write,
                        FileShare.Read
                    )
                );

            WriteWaveHeader();

            CreateBuffers();

            recording =
                true;

            int result =
                waveInStart(
                    waveHandle
                );

            ThrowIfError(
                result,
                "Starting microphone capture"
            );
        }
        catch
        {
            recording =
                false;

            CleanupAudio();

            if (writer != null)
            {
                writer.Close();

                writer =
                    null;
            }

            throw;
        }
    }


    // -----------------------------------------------------------------
    // Create capture buffers
    // -----------------------------------------------------------------

    private void CreateBuffers()
    {
        int blockAlign =
            channels *
            bitsPerSample /
            8;

        // Roughly 100 ms of audio per buffer.
        int bufferLength =
            (sampleRate / 10) *
            blockAlign;

        const int bufferCount =
            8;


        for (
            int i = 0;
            i < bufferCount;
            i++
        )
        {
            AudioBuffer buffer =
                new AudioBuffer();

            buffer.Length =
                bufferLength;

            buffer.DataPointer =
                Marshal.AllocHGlobal(
                    bufferLength
                );


            WAVEHDR header =
                new WAVEHDR();

            header.lpData =
                buffer.DataPointer;

            header.dwBufferLength =
                (uint)bufferLength;

            header.dwBytesRecorded =
                0;

            header.dwUser =
                IntPtr.Zero;

            header.dwFlags =
                0;

            header.dwLoops =
                0;

            header.lpNext =
                IntPtr.Zero;

            header.reserved =
                IntPtr.Zero;


            buffer.HeaderPointer =
                Marshal.AllocHGlobal(
                    Marshal.SizeOf(
                        typeof(WAVEHDR)
                    )
                );


            Marshal.StructureToPtr(
                header,
                buffer.HeaderPointer,
                false
            );


            int prepareResult =
                waveInPrepareHeader(
                    waveHandle,
                    buffer.HeaderPointer,
                    (uint)Marshal.SizeOf(
                        typeof(WAVEHDR)
                    )
                );


            ThrowIfError(
                prepareResult,
                "Preparing audio buffer"
            );


            int addResult =
                waveInAddBuffer(
                    waveHandle,
                    buffer.HeaderPointer,
                    (uint)Marshal.SizeOf(
                        typeof(WAVEHDR)
                    )
                );


            ThrowIfError(
                addResult,
                "Adding audio buffer"
            );


            buffers.Add(
                buffer
            );
        }
    }


    // -----------------------------------------------------------------
    // Audio callback
    // -----------------------------------------------------------------

    private void AudioCallback(
        IntPtr hwi,
        uint message,
        IntPtr instance,
        IntPtr param1,
        IntPtr param2
    )
    {
        if (message != WIM_DATA)
        {
            return;
        }

        if (param1 == IntPtr.Zero)
        {
            return;
        }


        lock (sync)
        {
            WAVEHDR header =
                (WAVEHDR)Marshal.PtrToStructure(
                    param1,
                    typeof(WAVEHDR)
                );


            if (header.dwBytesRecorded > 0)
            {
                int length =
                    (int)header.dwBytesRecorded;


                byte[] audio =
                    new byte[length];


                Marshal.Copy(
                    header.lpData,
                    audio,
                    0,
                    length
                );


                // Always process audio for the live meter.
                // In preview mode this updates peak/clipping
                // without writing anything to disk.
                ApplyGainAndCalculatePeak(
                    audio,
                    length
                );


                // Only write PCM data during an actual recording.
                if (writer != null)
                {
                    writer.Write(
                        audio,
                        0,
                        length
                    );


                    dataBytesWritten +=
                        length;
                }
            }


            // Return completed buffer to Windows while capture
            // remains active.
            if (
                (recording || previewing) &&
                waveHandle != IntPtr.Zero
            )
            {
                header.dwBytesRecorded =
                    0;


                Marshal.StructureToPtr(
                    header,
                    param1,
                    false
                );


                waveInAddBuffer(
                    waveHandle,
                    param1,
                    (uint)Marshal.SizeOf(
                        typeof(WAVEHDR)
                    )
                );
            }
        }
    }


    // -----------------------------------------------------------------
    // Apply software gain + determine post-gain peak
    // -----------------------------------------------------------------

    private void ApplyGainAndCalculatePeak(
        byte[] data,
        int length
    )
    {
        int maximum =
            0;


        // 16-bit signed little-endian PCM
        for (
            int i = 0;
            i + 1 < length;
            i += 2
        )
        {
            short originalSample =
                (short)(
                    data[i] |
                    (data[i + 1] << 8)
                );


            double amplified =
                originalSample *
                gainMultiplier;


            int processedSample;


            if (amplified > short.MaxValue)
            {
                processedSample =
                    short.MaxValue;

                Interlocked.Exchange(
                    ref clippingFlag,
                    1
                );
            }
            else if (amplified < short.MinValue)
            {
                processedSample =
                    short.MinValue;

                Interlocked.Exchange(
                    ref clippingFlag,
                    1
                );
            }
            else
            {
                processedSample =
                    (int)Math.Round(
                        amplified
                    );
            }


            short finalSample =
                (short)processedSample;


            // Write the amplified sample back to the PCM
            // byte array.
            data[i] =
                (byte)(
                    finalSample &
                    0xFF
                );


            data[i + 1] =
                (byte)(
                    (finalSample >> 8) &
                    0xFF
                );


            int amplitude =
                finalSample == short.MinValue
                ? 32768
                : Math.Abs(
                    (int)finalSample
                );


            if (amplitude > maximum)
            {
                maximum =
                    amplitude;
            }
        }


        // Keep the strongest peak received since the
        // GUI last read the meter.
        int existing =
            Volatile.Read(
                ref currentPeak
            );


        while (maximum > existing)
        {
            int original =
                Interlocked.CompareExchange(
                    ref currentPeak,
                    maximum,
                    existing
                );

            if (original == existing)
            {
                break;
            }

            existing =
                original;
        }
    }


    // -----------------------------------------------------------------
    // Meter output
    // -----------------------------------------------------------------

    public int GetPeakPercent()
    {
        int peak =
            Interlocked.Exchange(
                ref currentPeak,
                0
            );


        double percentage =
            peak /
            32768.0 *
            100.0;


        if (percentage < 0)
        {
            percentage =
                0;
        }


        if (percentage > 100)
        {
            percentage =
                100;
        }


        return (int)Math.Round(
            percentage
        );
    }


    // -----------------------------------------------------------------
    // Clipping status
    // -----------------------------------------------------------------

    public bool GetAndResetClipping()
    {
        return (
            Interlocked.Exchange(
                ref clippingFlag,
                0
            ) != 0
        );
    }


    // -----------------------------------------------------------------
    // Stop recording
    // -----------------------------------------------------------------

    public void Stop()
    {
        if (!recording)
        {
            return;
        }


        recording =
            false;


        if (waveHandle != IntPtr.Zero)
        {
            waveInStop(
                waveHandle
            );

            // Return all queued buffers.
            waveInReset(
                waveHandle
            );

            // Give final callbacks time to arrive before
            // freeing native buffers.
            Thread.Sleep(
                150
            );
        }


        lock (sync)
        {
            CleanupAudio();

            FinalizeWaveHeader();

            if (writer != null)
            {
                writer.Flush();

                writer.Close();

                writer =
                    null;
            }
        }
    }


    // -----------------------------------------------------------------
    // Native cleanup
    // -----------------------------------------------------------------

    private void CleanupAudio()
    {
        if (waveHandle == IntPtr.Zero)
        {
            return;
        }


        foreach (
            AudioBuffer buffer
            in buffers
        )
        {
            int attempts =
                0;


            while (attempts < 30)
            {
                int result =
                    waveInUnprepareHeader(
                        waveHandle,
                        buffer.HeaderPointer,
                        (uint)Marshal.SizeOf(
                            typeof(WAVEHDR)
                        )
                    );


                if (result == MMSYSERR_NOERROR)
                {
                    break;
                }


                if (result != WAVERR_STILLPLAYING)
                {
                    break;
                }


                Thread.Sleep(
                    20
                );


                attempts++;
            }


            if (buffer.HeaderPointer != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(
                    buffer.HeaderPointer
                );

                buffer.HeaderPointer =
                    IntPtr.Zero;
            }


            if (buffer.DataPointer != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(
                    buffer.DataPointer
                );

                buffer.DataPointer =
                    IntPtr.Zero;
            }
        }


        buffers.Clear();


        waveInClose(
            waveHandle
        );


        waveHandle =
            IntPtr.Zero;
    }


    // -----------------------------------------------------------------
    // Initial WAV header
    // -----------------------------------------------------------------

    private void WriteWaveHeader()
    {
        writer.Write(
            Encoding.ASCII.GetBytes(
                "RIFF"
            )
        );


        // RIFF size placeholder
        writer.Write(
            (uint)0
        );


        writer.Write(
            Encoding.ASCII.GetBytes(
                "WAVE"
            )
        );


        writer.Write(
            Encoding.ASCII.GetBytes(
                "fmt "
            )
        );


        writer.Write(
            (uint)16
        );


        writer.Write(
            (ushort)WAVE_FORMAT_PCM
        );


        writer.Write(
            (ushort)channels
        );


        writer.Write(
            (uint)sampleRate
        );


        ushort blockAlign =
            (ushort)(
                channels *
                bitsPerSample /
                8
            );


        uint byteRate =
            (uint)(
                sampleRate *
                blockAlign
            );


        writer.Write(
            byteRate
        );


        writer.Write(
            blockAlign
        );


        writer.Write(
            (ushort)bitsPerSample
        );


        writer.Write(
            Encoding.ASCII.GetBytes(
                "data"
            )
        );


        // Data-size placeholder
        writer.Write(
            (uint)0
        );
    }


    // -----------------------------------------------------------------
    // Finalize WAV header
    // -----------------------------------------------------------------

    private void FinalizeWaveHeader()
    {
        if (writer == null)
        {
            return;
        }


        Stream stream =
            writer.BaseStream;


        long currentPosition =
            stream.Position;


        // RIFF chunk length
        stream.Seek(
            4,
            SeekOrigin.Begin
        );


        writer.Write(
            (uint)(
                36 +
                dataBytesWritten
            )
        );


        // PCM data length
        stream.Seek(
            40,
            SeekOrigin.Begin
        );


        writer.Write(
            (uint)dataBytesWritten
        );


        stream.Seek(
            currentPosition,
            SeekOrigin.Begin
        );
    }


    // -----------------------------------------------------------------
    // Dispose
    // -----------------------------------------------------------------

    public void Dispose()
    {
        try
        {
            Stop();
        }
        catch
        {
        }


        try
        {
            CleanupAudio();
        }
        catch
        {
        }


        if (writer != null)
        {
            try
            {
                writer.Close();
            }
            catch
            {
            }

            writer =
                null;
        }
    }
}
"@



$novaReferences = @(
    [System.Drawing.Graphics].Assembly.Location
    [System.Windows.Forms.Form].Assembly.Location
)

Add-Type `
    -TypeDefinition $novaSource `
    -ReferencedAssemblies $novaReferences `
    -Language CSharp

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


# =====================================================================
# Helpers
# =====================================================================

function Get-NewRecordingPath {

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

    return Join-Path $recordingsDirectory "Recording_$timestamp.wav"
}


function Get-VideoRecordingPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AudioPath
    )

    $directory = Split-Path -Parent $AudioPath
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($AudioPath)

    return Join-Path $directory ($baseName + "_video.avi")
}


function Get-NovaVideoDevices {

    if (-not $script:ffmpegAvailable) {
        return @()
    }

    # FFmpeg writes DirectShow enumeration to stderr. Merge stderr into
    # stdout so PowerShell can parse it without showing a console window.
    $lines = & $ffmpegPath -hide_banner -list_devices true -f dshow -i dummy 2>&1

    $devices = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        $text = [string]$line

        # Only expose devices FFmpeg explicitly identifies as video.
        # The built-in HP camera on this machine enumerates as "(none)"
        # and cannot currently bind through DirectShow, so it is excluded.
        if ($text -match '"([^"]+)"\s+\(video\)') {
            $name = $matches[1]

            if (-not $devices.Contains($name)) {
                $devices.Add($name)
            }
        }
    }

    return $devices.ToArray()
}

function Get-NovaVideoModes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceName
    )

    if (-not $script:ffmpegAvailable) {
        return @()
    }

    $lines = & $ffmpegPath `
        -hide_banner `
        -f dshow `
        -list_options true `
        -i ('video=' + $DeviceName) 2>&1

    $modes = New-Object System.Collections.Generic.List[object]

    foreach ($line in $lines) {
        $text = [string]$line

        # Prefer native MJPEG modes because we can stream-copy them
        # during capture without expensive real-time re-encoding.
        if ($text -match 'vcodec=mjpeg\s+min s=(\d+)x(\d+)\s+fps=([\d\.]+)\s+max s=\d+x\d+\s+fps=([\d\.]+)') {

            $width  = [int]$matches[1]
            $height = [int]$matches[2]
            $minFps = [double]$matches[3]
            $maxFps = [double]$matches[4]

            $key = "$width`x$height@$maxFps"

            $alreadyExists = $false

            foreach ($existing in $modes) {
                if ($existing.Key -eq $key) {
                    $alreadyExists = $true
                    break
                }
            }

            if (-not $alreadyExists) {
                $modes.Add(
                    [PSCustomObject]@{
                        Key       = $key
                        Codec     = 'mjpeg'
                        Width     = $width
                        Height    = $height
                        MinFps    = $minFps
                        MaxFps    = $maxFps
                        Display   = "$width x $height @ $maxFps fps"
                    }
                )
            }
        }
    }

    return @(
        $modes |
        Sort-Object `
            @{ Expression = { $_.Width * $_.Height }; Descending = $true },
            @{ Expression = { $_.MaxFps }; Descending = $true }
    )
}


function Start-NovaVideoCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceName,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [object]$Mode
    )

    if (-not $script:ffmpegAvailable) {
        throw "Portable FFmpeg was not found at:`n$ffmpegPath"
    }

    if ($script:videoRecording) {
        throw "Video capture is already running."
    }

    $videoSize = "$($Mode.Width)x$($Mode.Height)"
    $frameRate = [string]$Mode.MaxFps
    $codec     = [string]$Mode.Codec

    # Capture the selected camera's native MJPEG mode without real-time
    # H.264 transcoding. This keeps CPU load low and minimizes frame loss.
    $arguments = @(
        '-hide_banner'
        '-loglevel', 'warning'
        '-f', 'dshow'
        '-rtbufsize', '256M'
        '-video_size', $videoSize
        '-framerate', $frameRate
        '-vcodec', $codec
        '-i', ('video="' + $DeviceName + '"')
        '-c:v', 'copy'
        '-y'
        ('"' + $OutputPath + '"')
    ) -join ' '

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $ffmpegPath
    $startInfo.Arguments = $arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    if (-not $process.Start()) {
        throw "FFmpeg could not start video capture."
    }

    # Give DirectShow a moment to bind the camera. If FFmpeg exits
    # immediately, surface that as a failed start instead of pretending
    # video is recording.
    Start-Sleep -Milliseconds 350

    if ($process.HasExited) {
        $exitCode = $process.ExitCode
        $process.Dispose()
        throw "FFmpeg exited before video capture started (exit code $exitCode)."
    }

    $script:videoProcess = $process
    $script:videoRecording = $true
}


function Stop-NovaVideoCapture {

    if (-not $script:videoRecording) {
        return
    }

    $process = $script:videoProcess

    try {
        if ($null -ne $process -and -not $process.HasExited) {
            # 'q' requests FFmpeg's normal shutdown path so AVI indexes and
            # headers are finalized cleanly.
            $process.StandardInput.WriteLine('q')
            $process.StandardInput.Flush()

            if (-not $process.WaitForExit(5000)) {
                $process.Kill()
                [void]$process.WaitForExit(2000)
            }
        }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }

        $script:videoProcess = $null
        $script:videoRecording = $false
    }
}


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

$form.Size = New-Object System.Drawing.Size(540, 755)

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

$micLabel.Location = New-Object System.Drawing.Point(45, 80)

$form.Controls.Add($micLabel)


# =====================================================================
# Microphone dropdown
# =====================================================================

$deviceCombo = New-Object System.Windows.Forms.ComboBox

$deviceCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$deviceCombo.Size = New-Object System.Drawing.Size(340, 30)

$deviceCombo.Location = New-Object System.Drawing.Point(45, 104)

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

$refreshButton.Location = New-Object System.Drawing.Point(400, 103)

$form.Controls.Add($refreshButton)


# =====================================================================
# Video capture controls
# =====================================================================

$videoLabel = New-Object System.Windows.Forms.Label
$videoLabel.Text = "Video source"
$videoLabel.ForeColor = [System.Drawing.Color]::Gainsboro
$videoLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$videoLabel.AutoSize = $true
$videoLabel.Location = New-Object System.Drawing.Point(45, 145)
$form.Controls.Add($videoLabel)

$videoCombo = New-Object System.Windows.Forms.ComboBox
$videoCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$videoCombo.Size = New-Object System.Drawing.Size(340, 30)
$videoCombo.Location = New-Object System.Drawing.Point(45, 169)
$videoCombo.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Controls.Add($videoCombo)

$videoCheckBox = New-Object System.Windows.Forms.CheckBox
$videoCheckBox.Text = "Capture"
$videoCheckBox.ForeColor = [System.Drawing.Color]::Gainsboro
$videoCheckBox.AutoSize = $true
$videoCheckBox.Location = New-Object System.Drawing.Point(400, 172)
$videoCheckBox.Checked = $true
$form.Controls.Add($videoCheckBox)

$videoModeLabel = New-Object System.Windows.Forms.Label
$videoModeLabel.Text = "Video mode"
$videoModeLabel.Location = New-Object System.Drawing.Point(48, 225)
$videoModeLabel.Size = New-Object System.Drawing.Size(100, 20)
$videoModeLabel.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($videoModeLabel)

$videoModeCombo = New-Object System.Windows.Forms.ComboBox
$videoModeCombo.Location = New-Object System.Drawing.Point(48, 245)
$videoModeCombo.Size = New-Object System.Drawing.Size(338, 24)
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

$levelLabel.Location = New-Object System.Drawing.Point(45, 220)

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

$clipLabel.Location = New-Object System.Drawing.Point(445, 222)

$form.Controls.Add($clipLabel)


# =====================================================================
# Input level bar
# =====================================================================

$headMeter = New-Object CyberHeadMeter

$headMeter.Size = New-Object System.Drawing.Size(180, 180)

$headMeter.Location = New-Object System.Drawing.Point(170, 240)

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

$gainTitleLabel.Location = New-Object System.Drawing.Point(45, 435)

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

$gainValueLabel.Location = New-Object System.Drawing.Point(430, 435)

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

$gainSlider.Size = New-Object System.Drawing.Size(390, 38)

$gainSlider.Location = New-Object System.Drawing.Point(40, 447)

$form.Controls.Add($gainSlider)


# Gain scale labels

$gainZeroLabel = New-Object System.Windows.Forms.Label
$gainZeroLabel.Text = "0"
$gainZeroLabel.ForeColor = [System.Drawing.Color]::Gray
$gainZeroLabel.AutoSize = $true
$gainZeroLabel.Location = New-Object System.Drawing.Point(48, 500)
$form.Controls.Add($gainZeroLabel)


$gainSixLabel = New-Object System.Windows.Forms.Label
$gainSixLabel.Text = "+8"
$gainSixLabel.ForeColor = [System.Drawing.Color]::Gray
$gainSixLabel.AutoSize = $true
$gainSixLabel.Location = New-Object System.Drawing.Point(139, 500)
$form.Controls.Add($gainSixLabel)


$gainTwelveLabel = New-Object System.Windows.Forms.Label
$gainTwelveLabel.Text = "+16"
$gainTwelveLabel.ForeColor = [System.Drawing.Color]::Gray
$gainTwelveLabel.AutoSize = $true
$gainTwelveLabel.Location = New-Object System.Drawing.Point(230, 500)
$form.Controls.Add($gainTwelveLabel)


$gainEighteenLabel = New-Object System.Windows.Forms.Label
$gainEighteenLabel.Text = "+32 dB"
$gainEighteenLabel.ForeColor = [System.Drawing.Color]::Gray
$gainEighteenLabel.AutoSize = $true
$gainEighteenLabel.Location = New-Object System.Drawing.Point(318, 500)
$form.Controls.Add($gainEighteenLabel)


$gainTwentyFourLabel = New-Object System.Windows.Forms.Label

$gainTwentyFourLabel.Text = "+24"
$gainTwentyFourLabel.ForeColor = [System.Drawing.Color]::Gray
$gainTwentyFourLabel.AutoSize = $true
$gainTwentyFourLabel.Location = New-Object System.Drawing.Point(405, 500)

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

$statusLabel.Location = New-Object System.Drawing.Point(200, 530)

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

$timerLabel.Location = New-Object System.Drawing.Point(185, 560)

$form.Controls.Add($timerLabel)


# =====================================================================
# Record button
# =====================================================================

$recordButton = New-Object System.Windows.Forms.Button

$recordButton.Text = "RECORD"

$recordButton.Size = New-Object System.Drawing.Size(145, 48)

$recordButton.Location = New-Object System.Drawing.Point(95, 615)

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

$stopButton.Location = New-Object System.Drawing.Point(285, 615)

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

$folderButton.Location = New-Object System.Drawing.Point(160, 675)

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

    foreach ($device in $devices) {
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

    if ($script:recording) {
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

    $script:currentFile = Get-NewRecordingPath
    $script:currentVideoFile = $null

    if ($videoCheckBox.Checked) {
        $script:currentVideoFile = Get-VideoRecordingPath -AudioPath $script:currentFile
    }


    try {

        $script:recorder.SetGainDb(
            [double]$gainSlider.Value
        )

        $script:recorder.Start(
            $device.Id,
            $script:currentFile
        )

        if ($videoCheckBox.Checked) {
    try {
        $selectedVideoMode = $videoModeCombo.SelectedItem
        

        if ($null -eq $selectedVideoMode) {
            throw "No video mode is selected."
        }

        $script:currentVideoMode = $selectedVideoMode

        Start-NovaVideoCapture `
            -DeviceName ([string]$videoCombo.SelectedItem) `
            -OutputPath $script:currentVideoFile `
            -Mode $selectedVideoMode
    }
            catch {
                # Audio already started. Stop it so RECORD remains atomic:
                # either both requested streams start, or neither does.
                try {
                    $script:recorder.Stop()
                }
                catch {
                }

                throw
            }
        }
    }
    catch {

        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "Nova Recorder",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )

        return
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

    if (-not $script:recording) {
        return
    }


    $uiTimer.Stop()


    $videoStopError = $null

    if ($script:videoRecording) {
        try {
            Stop-NovaVideoCapture
        }
        catch {
            $videoStopError = $_.Exception.Message
        }
    }

    try {

        $script:recorder.Stop()
    }
    catch {

        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "Nova Recorder",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }


    $script:recording = $false

    $script:recordingStart = $null


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


        $message =
            "Audio recording saved.`n`n" +
            "$script:currentFile`n`n" +
            "Format: $formatText`n" +
            "Gain: +$($gainSlider.Value) dB`n" +
            "Size: $sizeKB KB"

        if ($null -ne $script:currentVideoFile -and (Test-Path -LiteralPath $script:currentVideoFile)) {
            $videoInfo = Get-Item -LiteralPath $script:currentVideoFile
            $videoSizeMB = [Math]::Round($videoInfo.Length / 1MB, 1)

            $message +=
                "`n`nVideo recording saved separately:`n" +
                "$script:currentVideoFile`n" +
                "Format: $($script:currentVideoMode.Width)x$($script:currentVideoMode.Height), $($script:currentVideoMode.MaxFps) fps, native MJPEG`n" +
                "Size: $videoSizeMB MB"
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
# Open recordings folder
# =====================================================================

$folderButton.Add_Click({

    Start-Process -FilePath "explorer.exe" -ArgumentList "`"$recordingsDirectory`""
})


# =====================================================================
# Application closing
# =====================================================================

$form.Add_FormClosing({

    if ($script:recording) {

        $answer = [System.Windows.Forms.MessageBox]::Show(
            "A recording is currently running.`n`nStop and save it before closing?",
            "Nova Recorder",
            [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )


        if ($answer -eq [System.Windows.Forms.DialogResult]::Cancel) {

            $_.Cancel = $true

            return
        }


        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {

            try {

                $uiTimer.Stop()

                if ($script:videoRecording) {
                    Stop-NovaVideoCapture
                }

                $script:recorder.Stop()

                $script:recording = $false
            }
            catch {

                [System.Windows.Forms.MessageBox]::Show(
                    $_.Exception.Message,
                    "Nova Recorder",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )

                $_.Cancel = $true

                return
            }
        }
    }


    try {
        if ($script:videoRecording) {
            Stop-NovaVideoCapture
        }
    }
    catch {
    }

    try {
        $script:recorder.Dispose()
    }
    catch {
    }
})


# =====================================================================
# Startup
# =====================================================================

Update-DeviceList
Update-VideoDeviceList

$uiTimer.Start()

Start-LivePreview



[void]$form.ShowDialog()