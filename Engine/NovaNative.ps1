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

public class NovaFfmpegReadyMonitor : IDisposable
{
    private System.Diagnostics.Process process;
    private System.Threading.Thread monitorThread;
    private volatile bool stopping = false;
    private volatile bool videoReady = false;

    public bool VideoReady
    {
        get
        {
            return videoReady;
        }
    }

    public NovaFfmpegReadyMonitor(
        System.Diagnostics.Process ffmpegProcess
    )
    {
        process = ffmpegProcess;
    }

    public void Start()
    {
        stopping = false;
        videoReady = false;

        monitorThread =
            new System.Threading.Thread(MonitorLoop);

        monitorThread.IsBackground = true;
        monitorThread.Start();
    }

    private void MonitorLoop()
    {
        try
        {
            while (!stopping && !process.HasExited)
            {
                string line =
                    process.StandardError.ReadLine();

                if (line == null)
                {
                    break;
                }

                if (line.StartsWith("frame="))
                {
                    string value =
                        line.Substring(6).Trim();

                    int frameNumber;

                    if (
                        int.TryParse(
                            value,
                            out frameNumber
                        ) &&
                        frameNumber >= 1
                    )
                    {
                        videoReady = true;
                    }
                }
            }
        }
        catch
        {
            // Readiness telemetry must never crash recording.
        }
    }

    public void Dispose()
    {
        stopping = true;
    }
}

public class NovaPreviewReader : IDisposable
{
    private System.Diagnostics.Process process;
    private System.Windows.Forms.PictureBox pictureBox;
    private System.Threading.Thread readerThread;
    private volatile bool stopping = false;

    public NovaPreviewReader(
        System.Diagnostics.Process ffmpegProcess,
        System.Windows.Forms.PictureBox targetPictureBox
    )
    {
        process = ffmpegProcess;
        pictureBox = targetPictureBox;
    }

    public void Start()
    {
        stopping = false;

        readerThread =
            new System.Threading.Thread(ReadLoop);

        readerThread.IsBackground = true;
        readerThread.Start();
    }

    private void ReadLoop()
    {
        System.IO.Stream stream =
            process.StandardOutput.BaseStream;

        System.IO.MemoryStream frame =
            new System.IO.MemoryStream();

        byte[] buffer = new byte[65536];

        bool insideJpeg = false;
        int previous = -1;

        try
        {
            while (!stopping && !process.HasExited)
            {
                int bytesRead =
                    stream.Read(
                        buffer,
                        0,
                        buffer.Length
                    );

                if (bytesRead <= 0)
                {
                    break;
                }

                for (int i = 0; i < bytesRead; i++)
                {
                    int current = buffer[i];

                    if (!insideJpeg)
                    {
                        if (
                            previous == 0xFF &&
                            current == 0xD8
                        )
                        {
                            frame.SetLength(0);

                            frame.WriteByte(0xFF);
                            frame.WriteByte(0xD8);

                            insideJpeg = true;
                        }
                    }
                    else
                    {
                        frame.WriteByte(
                            (byte)current
                        );

                        if (
                            previous == 0xFF &&
                            current == 0xD9
                        )
                        {
                            byte[] jpegBytes =
                                frame.ToArray();

                            PublishFrame(jpegBytes);

                            insideJpeg = false;
                            frame.SetLength(0);
                        }
                    }

                    previous = current;
                }
            }
        }
        catch
        {
            // Preview failure must never crash NOVA Recorder.
        }
        finally
        {
            frame.Dispose();
        }
    }

    private void PublishFrame(byte[] jpegBytes)
    {
        try
        {
            System.Drawing.Bitmap bitmap;

            using (
                System.IO.MemoryStream memory =
                    new System.IO.MemoryStream(jpegBytes)
            )
            using (
                System.Drawing.Image image =
                    System.Drawing.Image.FromStream(memory)
            )
            {
                bitmap =
                    new System.Drawing.Bitmap(image);
            }

            if (
                pictureBox == null ||
                pictureBox.IsDisposed ||
                !pictureBox.IsHandleCreated
            )
            {
                bitmap.Dispose();
                return;
            }

            pictureBox.BeginInvoke(
                (System.Windows.Forms.MethodInvoker)delegate
                {
                    System.Drawing.Image oldImage =
                        pictureBox.Image;

                    pictureBox.Image = bitmap;

                    if (oldImage != null)
                    {
                        oldImage.Dispose();
                    }
                }
            );
        }
        catch
        {
            // Ignore malformed/incomplete preview frames.
        }
    }

    public void Dispose()
    {
        stopping = true;
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

    private bool firstBufferSeen = false;

    public long FirstBufferTimestamp { get; private set; }

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

        firstBufferSeen = false;
        FirstBufferTimestamp = 0;

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
                if (!firstBufferSeen)
                {
                    firstBufferSeen = true;
                    FirstBufferTimestamp = System.Diagnostics.Stopwatch.GetTimestamp();
                }
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
