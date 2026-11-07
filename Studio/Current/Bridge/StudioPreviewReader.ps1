# Isolated worker-only JPEG stdout drain. Does not modify NovaNative.ps1.
$previewSource = @'
using System;
using System.IO;
using System.Diagnostics;
using System.Threading;
public sealed class NovaStudioPreviewReader : IDisposable {
    private readonly Process process;
    private readonly string framePath;
    private Thread stdoutThread;
    private Thread stderrThread;
    private volatile bool stopping;
    private long frames;
    private long publishedFrames;
    private long writeFailures;
    private string error = "";
    public long Frames { get { return Interlocked.Read(ref frames); } }
    public long PublishedFrames { get { return Interlocked.Read(ref publishedFrames); } }
    public long WriteFailures { get { return Interlocked.Read(ref writeFailures); } }
    public string Error { get { return error; } }
    public NovaStudioPreviewReader(Process p, string path) { process=p; framePath=path; }
    public void Start() {
        stdoutThread=new Thread(ReadFrames); stdoutThread.IsBackground=true; stdoutThread.Start();
        stderrThread=new Thread(DrainErrors); stderrThread.IsBackground=true; stderrThread.Start();
    }
    public void StartWithoutStderr() {
        stdoutThread=new Thread(ReadFrames); stdoutThread.IsBackground=true; stdoutThread.Start();
    }
    private void DrainErrors() {
        try { while (!stopping && process.StandardError.ReadLine()!=null) {} }
        catch (Exception ex) { if (!stopping) error="FFmpeg stderr: "+ex.Message; }
    }
    private void ReadFrames() {
        // JPEG SOI/EOI stream parser; bounded frame bytes, latest-frame replacement supports up to 30 fps while FFmpeg outputs a maximum of 24 fps.
        // Every complete frame is counted even when intentionally skipped by the publisher.
        const int maxBytes = 8*1024*1024;
        byte[] buf=new byte[65536]; int previous=-1; bool inside=false;
        MemoryStream frame=new MemoryStream(1024*256);
        Stopwatch clock=Stopwatch.StartNew(); long lastWrite=-1000;
        try {
            Stream input=process.StandardOutput.BaseStream;
            while (!stopping) {
                int n=input.Read(buf,0,buf.Length); if(n<=0)break;
                for(int i=0;i<n;i++) {
                    int b=buf[i];
                    if (!inside) {
                        if(previous==255 && b==216) {
                            frame.SetLength(0); frame.WriteByte(255); frame.WriteByte(216); inside=true;
                        }
                    } else {
                        frame.WriteByte((byte)b);
                        if(frame.Length>maxBytes){ inside=false; frame.SetLength(0); }
                        else if(previous==255 && b==217) {
                            Interlocked.Increment(ref frames);
                            if(clock.ElapsedMilliseconds-lastWrite>=30) {
                                try { PublishFrame(frame.ToArray()); Interlocked.Increment(ref publishedFrames); lastWrite=clock.ElapsedMilliseconds; }
                                catch(Exception ex) { Interlocked.Increment(ref writeFailures); error="Preview frame publish: "+ex.Message; }
                            }
                            inside=false; frame.SetLength(0);
                        }
                    }
                    previous=b;
                }
            }
        } catch(Exception ex) { if(!stopping) error="Preview stdout: "+ex.Message; }
        finally { frame.Dispose(); }
    }
    private void PublishFrame(byte[] bytes) {
        string temp=framePath+"."+Guid.NewGuid().ToString("N")+".tmp";
        File.WriteAllBytes(temp,bytes);
        try {
            if (File.Exists(framePath)) {
                string backup=framePath+".bak";
                File.Replace(temp,framePath,backup);
                try { File.Delete(backup); } catch {}
            } else File.Move(temp,framePath);
        } finally { try { if(File.Exists(temp)) File.Delete(temp); } catch {} }
    }
    public void Dispose(){
        stopping=true;
        try { if(stdoutThread!=null)stdoutThread.Join(2000); } catch {}
        try { if(stderrThread!=null)stderrThread.Join(1000); } catch {}
    }
}
'@
Add-Type -TypeDefinition $previewSource -Language CSharp
