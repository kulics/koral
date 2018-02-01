using Antlr4.Runtime.Misc;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace coral
{
    partial class CoralVisitorBase : CoralBaseVisitor<object>
    {
        const string Wrap = "\r\n";

        public override object VisitProgram([NotNull] CoralParser.ProgramContext context)
        {
            var list = context.statement();
            var result = "";
            foreach(var item in list)
            {
                result += VisitStatement(item);
            }
            return result;
        }

        public override object VisitExpressionList([NotNull] CoralParser.ExpressionListContext context)
        {
            var r = new Result();
            var obj = "(";
            for(int i = 0; i < context.expression().Length; i++)
            {
                var temp = (Result)Visit(context.expression(i));
                if(i == 0)
                {
                    obj += temp.text;
                }
                else
                {
                    obj += ", " + temp.text;
                }
            }
            obj += ")";
            r.text = obj;
            r.data = "var";
            return r;
        }

        public override object VisitPrintStatement([NotNull] CoralParser.PrintStatementContext context)
        {
            var obj = "Console.WriteLine(" + context.Text().GetText() + ")" + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public class Result
        {
            public object data { get; set; }
            public string text { get; set; }
            public string permission { get; set; }
        }

        public override object VisitBool([NotNull] CoralParser.BoolContext context)
        {
            var r = new Result();
            if(context.t.Type == CoralParser.True)
            {
                r.data = "bool";
                r.text = context.True().GetText();
            }
            else if(context.t.Type == CoralParser.False)
            {
                r.data = "bool";
                r.text = context.False().GetText();
            }
            return r;
        }
        
    }
}
