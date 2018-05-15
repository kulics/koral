using Antlr4.Runtime;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace xylang
{
    static class Program
    {
        static void Main(string[] args)
        {
            //args = new[] { "build" };

            //if(args.Length > 0 && args[0] == "build")
            //{
                var path = @".\";
                Compiled(path);

                Console.WriteLine("Completed");
                Console.ReadKey();
            //}
        }

        static void Compiled(string path)
        {
            //获取相对路径下所有文件
            var files = Directory.GetFiles(path, "*.xy");
            foreach(var file in files)
            {
                // c#文件流读文件
                using(FileStream fsRead = new FileStream(file, FileMode.Open))
                {
                    try
                    {
                        var fsLen = (int)fsRead.Length;
                        var heByte = new byte[fsLen];
                        var r = fsRead.Read(heByte, 0, heByte.Length);
                        var input = Encoding.UTF8.GetString(heByte);

                        var stream = new AntlrInputStream(input);
                        var lexer = new XyLexer(stream);
                        var tokens = new CommonTokenStream(lexer);
                        var parser = new XyParser(tokens) { BuildParseTree = true };
                        var tree = parser.program();

                        var visitor = new XyLangVisitor();
                        var result = visitor.Visit(tree);

                        // C#文件流写文件,使用覆盖模式
                        var resByte = Encoding.UTF8.GetBytes(result.ToString());  //转换为字节
                        using(var fsWrite = new FileStream(@".\" + file.Substring(0, file.Length - 3) + ".cs", FileMode.Create))
                        {
                            fsWrite.Write(resByte, 0, resByte.Length);
                        };
                    }
                    catch(Exception err)
                    {
                        Console.Write("compile error at ");
                        Console.WriteLine(path + file);
                        Console.WriteLine(err);
                    }
                }
            }

            var folders = Directory.GetDirectories(path);
            foreach(var folder in folders)
            {
                Compiled(folder);
            }
        }
    }
}
