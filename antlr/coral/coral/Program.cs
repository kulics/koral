using Antlr4.Runtime;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace coral
{
    interface helper
    {
        int X { get; set; }
    }

    class help : helper
    {
        public int X { get; set; }
    }

    static class Program
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

    Main => $ 
    {
        print(""main function"");
        i => ""128.687"";  
        b => 12;  
        c => false; 
        ? 1+1 == 2
        {
            j => false;
            print(""judge"");
        };
        b.ToString().ToString();
        p => Program~();
        (x,y) => p.Square(str:""testcall"");
    };

    Program => # 
    { 
        i => 128.687;  
        b => ""12"";  
        c => true; 
        _PriName => "" program "";

        Square => $ (str:text)~(out1:number,out2:number)
        {
            @ 0..600 ~ i
            {
                print(""loop"");
                ? ^.c
                {
                    j => 1+1*3*9/8;
                    j = j + 5 +(j +8);
                }
                ~?
                {
                    j => (5>3)||false;
                    ~@;
                };
            };
            -> (1,2);
        };
        _Result => #~(name:text) 
        {
            ~^ => $
            {
                t => name;
            };
        };
    }; 

    Helper => |
    {
        b => 0;
        c => $(x:number)~(y:number){};
    };
};
";

            var stream = new AntlrInputStream(input);
            var lexer = new CoralLexer(stream);
            var tokens = new CommonTokenStream(lexer);
            var parser = new CoralParser(tokens) { BuildParseTree = true };
            var tree = parser.program();

            var visitor = new CoralVisitorBase();
            var result = visitor.Visit(tree);

            Console.WriteLine(tree.ToStringTree(parser));
            Console.WriteLine(result);
            Console.ReadKey();
        }
    }
}
