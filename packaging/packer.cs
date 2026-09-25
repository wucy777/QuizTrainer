// QuizTrainer 打包器：把 Flutter Windows 产物文件夹压成一个 payload。
//
// 用法: packer.exe <源文件夹> <输出文件>
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;

internal static class Packer
{
    private static readonly byte[] ArcMagic = Encoding.ASCII.GetBytes("QDARC100");

    private static int Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.Error.WriteLine("用法: packer.exe <源文件夹> <输出文件>");
            return 64;
        }
        string src = Path.GetFullPath(args[0]);
        string outFile = Path.GetFullPath(args[1]);
        if (!Directory.Exists(src))
        {
            Console.Error.WriteLine("源文件夹不存在: " + src);
            return 66;
        }

        List<string> rels = new List<string>();
        Collect(src, "", rels);
        rels.Sort(StringComparer.Ordinal);

        long rawTotal = 0;
        using (FileStream fs = new FileStream(outFile, FileMode.Create, FileAccess.Write))
        using (BinaryWriter bw = new BinaryWriter(fs))
        {
            bw.Write(ArcMagic, 0, ArcMagic.Length);
            bw.Write(rels.Count);

            byte[] buf = new byte[65536];
            foreach (string rel in rels)
            {
                string full = Path.Combine(src, rel.Replace('/', Path.DirectorySeparatorChar));
                byte[] raw = File.ReadAllBytes(full);
                rawTotal += raw.Length;

                byte[] nameB = Encoding.UTF8.GetBytes(rel);
                byte[] comp;
                using (MemoryStream ms = new MemoryStream())
                {
                    using (DeflateStream ds = new DeflateStream(ms, CompressionMode.Compress, true))
                    {
                        ds.Write(raw, 0, raw.Length);
                    }
                    comp = ms.ToArray();
                }

                bw.Write(nameB.Length);
                bw.Write(nameB, 0, nameB.Length);
                bw.Write((long)raw.Length);
                bw.Write((long)comp.Length);
                bw.Write(comp, 0, comp.Length);
            }
        }

        long outLen = new FileInfo(outFile).Length;
        Console.WriteLine("打包完成: " + rels.Count + " 个文件, 原始 "
            + (rawTotal / 1024) + " KB -> " + (outLen / 1024) + " KB");
        return 0;
    }

    private static void Collect(string root, string rel, List<string> outList)
    {
        string dir = string.IsNullOrEmpty(rel) ? root : Path.Combine(root, rel);
        foreach (string f in Directory.GetFiles(dir))
        {
            string name = Path.GetFileName(f);
            outList.Add(string.IsNullOrEmpty(rel) ? name : rel + "/" + name);
        }
        foreach (string d in Directory.GetDirectories(dir))
        {
            string name = Path.GetFileName(d);
            Collect(root, string.IsNullOrEmpty(rel) ? name : rel + "/" + name, outList);
        }
    }
}
