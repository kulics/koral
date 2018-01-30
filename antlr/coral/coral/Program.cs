using Antlr4.Runtime;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace coral
{
    class Program
    {
        static void Main(string[] args)
        {
            var input = @"
:> demo 
{ 
    <: 
    {   
        System;
        System.Linq;
    }; 

    Program => # 
    { 
        i => 128.687;  
        b => ""12"";  
        c => true; 
        
        Main => $ 
        {
            print(""main function"");
            i => ""128.687"";  
            b => 12;  
            c => false; 
            ? true
            {
                j => false;
                print(""judge"");
            };
        };

        Square => $ (text)~number
        {
            @ 0 .. 600
            {
                print(""loop"");
                ? true
                {
                    j => 1+1*3*9/8;
                    j = j + 5 +(j +8);
                }
                ~?
                {
                    j => (5>3)||false;
                };
            };
        };
    }; 
};
";

            var stream = new AntlrInputStream(input);
            var lexer = new CoralLexer(stream);
            var tokens = new CommonTokenStream(lexer);
            var parser = new CoralParser(tokens) { BuildParseTree = true };
            var tree = parser.program();

            var visitor = new CoralVisitor();
            var result = visitor.Visit(tree);

            Console.WriteLine(tree.ToStringTree(parser));
            Console.WriteLine(result);
            Console.ReadKey();
        }
    }
}