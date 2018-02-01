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

        public class Iterator
        {
            public double from { get; set; }
            public double to { get; set; }
            public double step { get; set; }
        }

        public override object VisitIteratorStatement([NotNull] CoralParser.IteratorStatementContext context)
        {
            var it = new Iterator();
            var i = context.Number();
            if(context.Number().Length == 2)
            {
                it.from = Convert.ToDouble(context.Number(0).GetText());
                it.to = Convert.ToDouble(context.Number(1).GetText());
                it.step = 1;
            }
            else
            {
                it.from = Convert.ToDouble(context.Number(0).GetText());
                it.to = Convert.ToDouble(context.Number(2).GetText());
                it.step = Convert.ToDouble(context.Number(1).GetText());
            }
            return it;
        }

        public override object VisitLoopStatement([NotNull] CoralParser.LoopStatementContext context)
        {
            var obj = "";
            var id = (Result)Visit(context.id());
            var it = (Iterator)Visit(context.iteratorStatement());
            obj += "for (double " + id.text + " = " + it.from.ToString() + ";";
            if(it.from <= it.to)
            {
                obj += id.text + "<" + it.to.ToString() + ";";
                obj += id.text + "+=" + it.step.ToString() + ")";
            }
            else
            {
                obj += id.text + ">" + it.to.ToString() + ";";
                obj += id.text + "-=" + it.step.ToString() + ")";
            }
            obj += Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.logicStatement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitLoopInfiniteStatement([NotNull] CoralParser.LoopInfiniteStatementContext context)
        {
            var obj = "while (true)" + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.logicStatement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitJudgeWithElseStatement([NotNull] CoralParser.JudgeWithElseStatementContext context)
        {
            var obj = Visit(context.judgeBaseStatement()) + Wrap + " else " + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.logicStatement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitJudgeStatement([NotNull] CoralParser.JudgeStatementContext context)
        {
            var obj = Visit(context.judgeBaseStatement()) + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitJudgeBaseStatement([NotNull] CoralParser.JudgeBaseStatementContext context)
        {
            var b = (Result)Visit(context.expression());
            var obj = "if (" + b.text + ")" + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.logicStatement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText();
            return obj;
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
