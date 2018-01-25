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
            i => ""128.687"";  
            b => 12;  
            c => false; 
        };

        Square => $ (text)~number
        {
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