using Antlr4.Runtime.Misc;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace coral
{
    partial class CoralVisitorBase
    {
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

        public override object VisitLoopEachStatement([NotNull] CoralParser.LoopEachStatementContext context)
        {
            var obj = "";
            var id = (Result)Visit(context.id());
            var arr = (Result)Visit(context.expression());
            obj += "foreach (var " + id.text + " in " + arr.text + ")";
            obj += Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.logicStatement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitLoopJumpStatement([NotNull] CoralParser.LoopJumpStatementContext context)
        {
            return "break" + context.Terminate().GetText() + Wrap;
        }

        public override object VisitJudgeCaseStatement([NotNull] CoralParser.JudgeCaseStatementContext context)
        {
            var obj = "";
            var expr = (Result)Visit(context.expression());
            obj += "switch (" + expr.text + ")" + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.caseStatement())
            {
                var r = (string)Visit(item);
                obj += r + Wrap;
            }
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitCaseStatement([NotNull] CoralParser.CaseStatementContext context)
        {
            var obj = "";
            var expr = (Result)Visit(context.expression());
            obj += "case " + expr.text + ":" + Wrap;
            foreach(var item in context.logicStatement())
            {
                var r = (string)Visit(item);
                obj += r;
            }
            obj += "break;";
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
    }
}