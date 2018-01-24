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
            //string input = @"Int = 1*2*3;";
            var input = @" i => 128; b => 12; c => 4;";

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
