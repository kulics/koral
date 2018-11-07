using Antlr4.Runtime;
using System;
using System.IO;
using System.Text;

namespace Compiler
{
    internal static class Compiler
    {
        private static string readPath;
        private static string pathLine;

        private static void Main(string[] args)
        {
            // 检查系统平台，区分路径字符
            var os = Environment.OSVersion.Platform;
            if (os == PlatformID.Unix || os == PlatformID.MacOSX)
            {
                readPath = @"./";
                pathLine = @"/";
            }
            else
            {
                readPath = @".\";
                pathLine = @"\";
            }

            //args = new[] { "build" };

            //if(args.Length > 0 && args[0] == "build")
            //{
            Compiled(readPath);

            Console.WriteLine("Completed");
            Console.ReadKey();
            //}
        }

        private static void Compiled(string path)
        {
            //获取相对路径下所有文件
            var files = Directory.GetFiles(path, "*.xs");
            foreach (var file in files)
            {
                // c#文件流读文件
                using (FileStream fsRead = new FileStream(file, FileMode.Open))
                {
                    try
                    {
                        var fsLen = (int)fsRead.Length;
                        var heByte = new byte[fsLen];
                        var r = fsRead.Read(heByte, 0, heByte.Length);
                        var input = Encoding.UTF8.GetString(heByte);

                        var stream = new AntlrInputStream(input);
                        var lexer = new XsLexer(stream);
                        var tokens = new CommonTokenStream(lexer);
                        var parser = new XsParser(tokens) { BuildParseTree = true };
                        parser.RemoveErrorListeners();
                        parser.AddErrorListener(new ErrorListener(file));

                        var tree = parser.program();

                        var fileName = "";
                        if (file.LastIndexOf(pathLine) > 0)
                        {
                            var index = file.LastIndexOf(pathLine);
                            fileName = file.Substring(index + 1, file.Length - (index + 1) - 3);
                        }
                        else
                        {
                            fileName = file.Substring(0, file.Length - 3);
                        }

                        var visitor = new Visitor() { FileName = fileName };
                        var result = visitor.Visit(tree);

                        // C#文件流写文件,使用覆盖模式
                        var resByte = Encoding.UTF8.GetBytes(result.ToString());  //转换为字节
                        using (var fsWrite = new FileStream(readPath + file.Substring(0, file.Length - 3) + ".cs", FileMode.Create))
                        {
                            fsWrite.Write(resByte, 0, resByte.Length);
                        };
                    }
                    catch (Exception err)
                    {
                        Console.WriteLine(err);
                    }
                }
            }

            var folders = Directory.GetDirectories(path);
            foreach (var folder in folders)
            {
                Compiled(folder);
            }
        }
    }
}
