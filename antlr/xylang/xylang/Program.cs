using Antlr4.Runtime;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace xylang
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
                    j => false;
                }
                ~?
                {
                    j => true;
                };
            };
        };
    }; 
};
";

            var stream = new AntlrInputStream(input);
            var lexer = new GrammarLexer(stream);
            var tokens = new CommonTokenStream(lexer);
            var parser = new GrammarParser(tokens) { BuildParseTree = true };
            var tree = parser.program();

            var visitor = new GrammarVisitor();
            var result = visitor.Visit(tree);

            Console.WriteLine(tree.ToStringTree(parser));
            Console.WriteLine(result);
            Console.ReadKey();
        }
    }
}


namespace demo
{
    using System;
    class Program
    {
        double i = 128.687;
        string b = "12";
        bool c = true;
        static void Main(string[] args)
        {
            Console.WriteLine("main function");
            string i = "128.687";
            double b = 12;
            bool c = false;
            if (true)
            {
                bool j = false;
                Console.WriteLine("judge");
            };
        }
        void Square(string p)
        {
            for (double i = 0; i < 600; i++)
            {
                Console.WriteLine("loop");
                if (true)
                {
                    bool j = false;
                }
                else
                {
                    bool j = true;
                };
            };
        }
    };
};