using Antlr4.Runtime;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace coral
{
    static class Program
    {
        static void Main(string[] args)
        {
            var path = @".\";

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
                        var lexer = new CoralLexer(stream);
                        var tokens = new CommonTokenStream(lexer);
                        var parser = new CoralParser(tokens) { BuildParseTree = true };
                        var tree = parser.program();

                        var visitor = new CoralVisitorBase();
                        var result = visitor.Visit(tree);

                        //Console.WriteLine(tree.ToStringTree(parser));
                        //Console.WriteLine(result);

                        // C#文件流写文件,使用覆盖模式
                        var resByte = Encoding.UTF8.GetBytes(result.ToString());  //转换为字节
                        using(var fsWrite = new FileStream(@".\" + file.Substring(0, file.Length - 3) + ".cs", FileMode.Create))
                        {
                            fsWrite.Write(resByte, 0, resByte.Length);
                        };
                    }
                    catch(Exception err)
                    {
                        Console.WriteLine(err);
                    }
                }
            }
            Console.WriteLine("Completed");
            Console.ReadKey();
        }
    }
}