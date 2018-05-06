using Antlr4.Runtime.Misc;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace xylang
{
    partial class XyLangVisitor
    {
        public class Iterator
        {
            public Result from { get; set; }
            public Result to { get; set; }
            public Result step { get; set; }
        }

        public override object VisitIteratorStatement([NotNull] XyParser.IteratorStatementContext context)
        {
            var it = new Iterator();
            var i = context.expression();
            if(context.expression().Length == 2)
            {
                it.from = (Result)Visit(context.expression(0));
                it.to = (Result)Visit(context.expression(1));
                it.step = new Result { data = "int", text = "1" };
            }
            else
            {
                it.from = (Result)Visit(context.expression(0));
                it.to = (Result)Visit(context.expression(1));
                it.step = (Result)Visit(context.expression(2));
            }
            return it;
        }

        public override object VisitLoopStatement([NotNull] XyParser.LoopStatementContext context)
        {
            var obj = "";
            var id = (Result)Visit(context.id());
            var it = (Iterator)Visit(context.iteratorStatement());
            obj += "for (var " + id.text + " = " + it.from.text + ";";
            obj += id.text + "!=" + it.to.text + "+" + it.step.text + ";";
            obj += id.text + "+=" + it.step.text + ")";
            obj += Wrap + context.BlockLeft().GetText() + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitLoopInfiniteStatement([NotNull] XyParser.LoopInfiniteStatementContext context)
        {
            var obj = "for (;;)" + Wrap + context.BlockLeft().GetText() + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitLoopEachStatement([NotNull] XyParser.LoopEachStatementContext context)
        {
            var obj = "";
            var id = (Result)Visit(context.id());
            var arr = (Result)Visit(context.expression());
            obj += "foreach (var " + id.text + " in " + arr.text + ")";
            obj += Wrap + context.BlockLeft().GetText() + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitLoopJumpStatement([NotNull] XyParser.LoopJumpStatementContext context)
        {
            return "break" + context.Terminate().GetText() + Wrap;
        }

        public override object VisitJudgeCaseStatement([NotNull] XyParser.JudgeCaseStatementContext context)
        {
            var obj = "";
            var expr = (Result)Visit(context.expression());
            obj += "switch (" + expr.text + ")" + Wrap + "{" + Wrap;
            foreach(var item in context.caseStatement())
            {
                var r = (string)Visit(item);
                obj += r + Wrap;
            }
            obj += "}" + Wrap;
            return obj;
        }

        public override object VisitCaseDefaultStatement([NotNull] XyParser.CaseDefaultStatementContext context)
        {
            var obj = "";
            obj += "default:" + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += "break;";
            return obj;
        }

        public override object VisitCaseExprStatement([NotNull] XyParser.CaseExprStatementContext context)
        {
            var obj = "";
            var expr = (Result)Visit(context.expression());
            obj += "case " + expr.text + ":" + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += "break;";
            return obj;
        }

        public override object VisitCaseStatement([NotNull] XyParser.CaseStatementContext context)
        {
            var obj = (string)Visit(context.GetChild(0));
            return obj;
        }

        public override object VisitJudgeStatement([NotNull] XyParser.JudgeStatementContext context)
        {
            var obj = "";
            for(int i = 0; i < context.judgeBaseStatement().Length; i++)
            {
                if(i == 0)
                {
                    obj += Visit(context.judgeBaseStatement(i));
                }
                else
                {
                    obj += "else " + Visit(context.judgeBaseStatement(i));
                }
            }
            if(context.judgeElseStatement() != null)
            {
                obj += Visit(context.judgeElseStatement());
            }
            return obj;
        }

        public override object VisitJudgeBaseStatement([NotNull] XyParser.JudgeBaseStatementContext context)
        {
            var b = (Result)Visit(context.expression());
            var obj = "if (" + b.text + ")" + Wrap + context.BlockLeft().GetText() + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitJudgeElseStatement([NotNull] XyParser.JudgeElseStatementContext context)
        {
            var obj = "else " + Wrap + context.BlockLeft().GetText() + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitCheckStatement([NotNull] XyParser.CheckStatementContext context)
        {
            var obj = "";
            obj += "try " + context.BlockLeft().GetText() + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += context.BlockRight().GetText() + Wrap;
            obj += Visit(context.checkErrorStatement()) + Wrap;
            return obj;
        }

        public override object VisitCheckErrorStatement([NotNull] XyParser.CheckErrorStatementContext context)
        {
            var obj = "";
            var ID = (Result)Visit(context.id());
            obj += "catch(Exception " + ID.text + ")" + Wrap + context.BlockLeft().GetText() + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += context.BlockRight().GetText();
            return obj;
        }

        public override object VisitReportStatement([NotNull] XyParser.ReportStatementContext context)
        {
            var obj = "";
            if(context.expression() != null)
            {
                var r = (Result)Visit(context.expression());
                obj += r.text;
            }
            return "throw " + obj + context.Terminate().GetText() + Wrap;
        }

        public override object VisitCheckDeferStatement([NotNull] XyParser.CheckDeferStatementContext context)
        {
            var obj = "";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            return obj;
        }

        public override object VisitLinq([NotNull] XyParser.LinqContext context)
        {
            var r = new Result();
            r.data = "var";
            foreach(var item in context.linqItem())
            {
                r.text += (string)Visit(item) + " ";
            }
            r.text = "(" + r.text + ")";
            return r;
        }

        public override object VisitLinqItem([NotNull] XyParser.LinqItemContext context)
        {
            if(context.expression() != null)
            {
                return ((Result)Visit(context.expression())).text;
            }
            return (string)Visit(context.linqKeyword());
        }

        public override object VisitLinqKeyword([NotNull] XyParser.LinqKeywordContext context)
        {
            return context.k.Text;
        }
    }
}
