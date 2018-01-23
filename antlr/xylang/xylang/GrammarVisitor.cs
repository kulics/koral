using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Antlr4.Runtime.Misc;
using xylang;

namespace xylang
{
    class GrammarVisitor : GrammarBaseVisitor<object>
    {
        Dictionary<string, object> memory = new Dictionary<string, object>();

        public override object VisitParens([NotNull] GrammarParser.ParensContext context)
        {
            return Visit(context.expr());
        }

        public override object VisitPrint([NotNull] GrammarParser.PrintContext context)
        {
            var obj = new object();
            
            return base.VisitPrint(context);
        }

        public override object VisitId([NotNull] GrammarParser.IdContext context)
        {
            return base.VisitId(context);
        }

        public override object VisitMulDiv([NotNull] GrammarParser.MulDivContext context)
        {
            double left = Convert.ToDouble(Visit(context.expr(0)));
            double right = Convert.ToDouble(Visit(context.expr(1)));

            object obj = new object();
            if (context.op.Type == GrammarParser.Mul)
            {
                obj = left * right;
            }
            else if (context.op.Type == GrammarParser.Div)
            {
                if (right == 0)
                {
                    throw new Exception("Cannot divide by zero.");
                }
                obj = left / right;
            }

            return obj;
        }

        public override object VisitAddSub([NotNull] GrammarParser.AddSubContext context)
        {
            double left = Convert.ToDouble(Visit(context.expr(0)));
            double right = Convert.ToDouble(Visit(context.expr(1)));

            object obj = new object();
            if (context.op.Type == GrammarParser.Add)
            {
                obj = left + right;
            }
            else if (context.op.Type == GrammarParser.Sub)
            {
                obj = left - right;
            }
            return obj;
        }

        public override object VisitNumber([NotNull] GrammarParser.NumberContext context)
        {
            object obj = context.GetText();
            return obj;
        }
    }
}
