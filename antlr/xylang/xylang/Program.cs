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
            var input = @"1 + (2*3);";

            var stream = new AntlrInputStream(input);
            var lexer = new GrammarLexer(stream);
            var tokens = new CommonTokenStream(lexer);
            var parser = new GrammarParser(tokens);
            var tree = parser.prog();

            var visitor = new GrammarVisitor();
            var result = visitor.Visit(tree);

            Console.WriteLine(tree.ToStringTree(parser));
            Console.WriteLine(result);
            Console.ReadKey();
        }
    }
}
