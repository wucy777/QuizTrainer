// QuizTrainer 单文件启动器（PyInstaller onefile 行为）
//
// Flutter Windows 产物是「文件夹」（exe + flutter_windows.dll + data\），
// 本启动器把整个文件夹压缩后附加在自己尾部，运行时：
//   1. 解压到 %TEMP%\QuizTrainer_<本进程PID>
//   2. 启动真正的 QuizTrainer.exe 并等待其退出
//   3. 退出时删除该临时目录，不留残留
//
// 单文件格式：
//   [本启动器 exe][payload 字节][8 字节 payload 长度(Int64 LE)][8 字节 "QDRILLPK"]
//
// payload 内部格式（QDARC100）：
//   "QDARC100"(8) | 文件数(Int32) | 每项: 名字长(Int32) 名字(UTF8) 原始长(Int64)
//                                        压缩长(Int64) Deflate 数据
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

internal static class Launcher
{
    private static readonly byte[] ArcMagic = Encoding.ASCII.GetBytes("QDARC100");
    private const string PayloadMagic = "QDRILLPK";
    private const string TempPrefix = "QuizTrainer_";
    private const string AppExe = "QuizTrainer.exe";

    [STAThread]
    private static int Main(string[] args)
    {
        string tempRoot = Path.GetTempPath();
        string appDir = Path.Combine(tempRoot, TempPrefix + Process.GetCurrentProcess().Id);
        int code = 0;

        try
        {
            // 清理上次异常退出（崩溃/断电）残留的临时目录：只删 1 小时以上的，
            // 避免误删正在运行的另一个实例。
            CleanStale(tempRoot, TimeSpan.FromHours(1));

            if (Directory.Exists(appDir)) TryDelete(appDir);
            Directory.CreateDirectory(appDir);

            byte[] payload = ReadPayload(Assembly.GetExecutingAssembly().Location);
            if (payload == null)
            {
                Fail("未能读取内置程序数据，文件可能已损坏。");
                return 2;
            }
            Extract(payload, appDir);

            string exe = Path.Combine(appDir, AppExe);
            if (!File.Exists(exe))
            {
                Fail("解压后未找到 " + AppExe + "。");
                return 3;
            }

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = exe;
            psi.WorkingDirectory = appDir;
            psi.UseShellExecute = false;
            if (args != null && args.Length > 0) psi.Arguments = JoinArgs(args);

            using (Process child = Process.Start(psi))
            {
                if (child != null) child.WaitForExit();
            }
        }
        catch (Exception ex)
        {
            Fail("启动失败：" + ex.Message);
            code = 1;
        }
        finally
        {
            // 关掉程序后清掉临时目录
            Cleanup(appDir);
        }
        return code;
    }

    /// <summary>退出时清理；子进程刚结束可能还占着文件句柄，重试几次。</summary>
    private static void Cleanup(string appDir)
    {
        for (int i = 0; i < 10; i++)
        {
            if (!Directory.Exists(appDir)) return;
            if (TryDelete(appDir)) return;
            Thread.Sleep(200);
        }
        // 最后再试一次，失败就算了（下次启动会按“1 小时以上”规则清掉）
        TryDelete(appDir);
    }

    /// <summary>清理历史残留的 QuizTrainer_* 临时目录。</summary>
    private static void CleanStale(string tempRoot, TimeSpan minAge)
    {
        try
        {
            DateTime cutoff = DateTime.Now - minAge;
            foreach (string d in Directory.GetDirectories(tempRoot, TempPrefix + "*"))
            {
                try
                {
                    if (Directory.GetCreationTime(d) < cutoff) TryDelete(d);
                }
                catch
                {
                    // 单个目录失败不影响其它
                }
            }
        }
        catch
        {
            // TEMP 不可枚举时忽略
        }
    }

    private static bool TryDelete(string dir)
    {
        try
        {
            if (Directory.Exists(dir))
            {
                Directory.Delete(dir, true);
            }
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static string JoinArgs(string[] args)
    {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < args.Length; i++)
        {
            if (i > 0) sb.Append(' ');
            string a = args[i];
            if (a.IndexOf(' ') >= 0)
            {
                sb.Append('"').Append(a.Replace("\"", "\\\"")).Append('"');
            }
            else
            {
                sb.Append(a);
            }
        }
        return sb.ToString();
    }

    private static byte[] ReadPayload(string self)
    {
        using (FileStream fs = new FileStream(self, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            long total = fs.Length;
            if (total < 16) return null;

            byte[] magic = new byte[8];
            fs.Seek(total - 8, SeekOrigin.Begin);
            if (fs.Read(magic, 0, 8) != 8) return null;
            if (Encoding.ASCII.GetString(magic) != PayloadMagic) return null;

            byte[] lenBytes = new byte[8];
            fs.Seek(total - 16, SeekOrigin.Begin);
            if (fs.Read(lenBytes, 0, 8) != 8) return null;
            long plen = BitConverter.ToInt64(lenBytes, 0);

            long off = total - 16 - plen;
            if (off < 0 || plen <= 0 || plen > int.MaxValue) return null;

            byte[] data = new byte[plen];
            fs.Seek(off, SeekOrigin.Begin);
            int read = 0;
            while (read < plen)
            {
                int n = fs.Read(data, read, (int)(plen - read));
                if (n <= 0) break;
                read += n;
            }
            return read == plen ? data : null;
        }
    }

    private static void Extract(byte[] data, string dir)
    {
        int p = 0;
        for (int i = 0; i < ArcMagic.Length; i++)
        {
            if (data[p + i] != ArcMagic[i]) throw new InvalidDataException("内置数据头无效");
        }
        p += ArcMagic.Length;

        int count = BitConverter.ToInt32(data, p);
        p += 4;

        byte[] buf = new byte[65536];
        for (int i = 0; i < count; i++)
        {
            int nameLen = BitConverter.ToInt32(data, p);
            p += 4;
            string name = Encoding.UTF8.GetString(data, p, nameLen);
            p += nameLen;

            long rawLen = BitConverter.ToInt64(data, p);
            p += 8;
            long compLen = BitConverter.ToInt64(data, p);
            p += 8;

            string full = Path.Combine(dir, name.Replace('/', Path.DirectorySeparatorChar));
            string parent = Path.GetDirectoryName(full);
            if (!string.IsNullOrEmpty(parent)) Directory.CreateDirectory(parent);

            using (MemoryStream ms = new MemoryStream(data, p, (int)compLen, false))
            using (DeflateStream ds = new DeflateStream(ms, CompressionMode.Decompress))
            using (FileStream outFs = new FileStream(full, FileMode.Create, FileAccess.Write))
            {
                long written = 0;
                int n;
                while ((n = ds.Read(buf, 0, buf.Length)) > 0)
                {
                    outFs.Write(buf, 0, n);
                    written += n;
                }
                if (written != rawLen)
                {
                    throw new InvalidDataException("解压长度不符：" + name);
                }
            }
            p += (int)compLen;
        }
    }

    private static void Fail(string msg)
    {
        MessageBox.Show(msg, "QuizTrainer", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }
}
