using Antlr4.Runtime.Misc;

namespace XyLang.Compile
{
    internal partial class XyLangVisitor
    {
        public class Iterator
        {
            public Result from { get; set; }
            public Result to { get; set; }
            public Result step { get; set; }
            public string op { get; set; }
        }

        public override object VisitIteratorStatement([NotNull] XyParser.IteratorStatementContext context)
        {
            var it = new Iterator();
            var i = context.expression();

            it.op = context.op.Text;
            if (context.expression().Length == 2)
            {
                it.from = (Result)Visit(context.expression(0));
                it.to = (Result)Visit(context.expression(1));
                it.step = new Result { data = I32, text = "1" };
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
            var id = "it";
            if (context.id() != null)
            {
                id = ((Result)Visit(context.id())).text;
            }
            var it = (Iterator)Visit(context.iteratorStatement());
            obj += $"for (var {id} = {it.from.text};";
            if (it.op == ">" || it.op == ">=")
            {
                obj += $"{id} {it.op} {it.to.text};";
                obj += $"{id} -= {it.step.text})";
            }
            else
            {
                obj += $"{id} {it.op} {it.to.text};";
                obj += $"{id} += {it.step.text})";
            }

            obj += $"{Wrap} {BlockLeft} {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += $"{BlockRight} {Terminate} {Wrap}";
            return obj;
        }

        public override object VisitLoopInfiniteStatement([NotNull] XyParser.LoopInfiniteStatementContext context)
        {
            var obj = $"for (;;) {Wrap} {BlockLeft} {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += $"{BlockRight} {Terminate} {Wrap}";
            return obj;
        }

        public override object VisitLoopEachStatement([NotNull] XyParser.LoopEachStatementContext context)
        {
            var obj = "";
            var arr = (Visit(context.expression()) as Result);
            var target = arr.text;
            var id = "it";
            if (context.id().Length == 2)
            {
                target += ".xyRange()";
                id = $"({((Result)Visit(context.id(0))).text},{((Result)Visit(context.id(1))).text})";
            }
            else if (context.id().Length == 1)
            {
                id = ((Result)Visit(context.id(0))).text;
            }

            obj += $"foreach (var {id} in {target})";
            obj += $"{Wrap} {BlockLeft} {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += $"{BlockRight} {Terminate} {Wrap}";
            return obj;
        }

        public override object VisitLoopCaseStatement([NotNull] XyParser.LoopCaseStatementContext context)
        {
            var obj = "";
            var expr = (Result)Visit(context.expression());
            obj += $"for ( ;{expr.text} ;)";
            obj += $"{Wrap} {BlockLeft} {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += $"{BlockRight} {Terminate} {Wrap}";
            return obj;
        }

        public override object VisitLoopJumpStatement([NotNull] XyParser.LoopJumpStatementContext context)
        {
            return $"break {Terminate} {Wrap}";
        }

        public override object VisitJudgeCaseStatement([NotNull] XyParser.JudgeCaseStatementContext context)
        {
            var obj = "";
            var expr = (Result)Visit(context.expression());
            obj += $"switch ({expr.text}) {Wrap} {{ {Wrap}";
            foreach (var item in context.caseStatement())
            {
                var r = (string)Visit(item);
                obj += r + Wrap;
            }
            obj += $"}} {Wrap}";
            return obj;
        }

        public override object VisitCaseDefaultStatement([NotNull] XyParser.CaseDefaultStatementContext context)
        {
            var obj = "";
            obj += $"default:{{ {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += "}break;";
            return obj;
        }

        public override object VisitCaseExprStatement([NotNull] XyParser.CaseExprStatementContext context)
        {
            var obj = "";
            if (context.type() is null)
            {
                var expr = (Result)Visit(context.expression());
                obj += $"case {expr.text} :{Wrap}";
            }
            else
            {
                var id = "it";
                if (context.id() != null)
                {
                    id = ((Result)Visit(context.id())).text;
                }
                var type = (string)Visit(context.type());
                obj += $"case {type} {id} :{Wrap}";
            }

            obj += $"{{ {ProcessFunctionSupport(context.functionSupportStatement())} }}";
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
            for (int i = 0; i < context.judgeBaseStatement().Length; i++)
            {
                if (i == 0)
                {
                    obj += Visit(context.judgeBaseStatement(i));
                }
                else
                {
                    obj += "else " + Visit(context.judgeBaseStatement(i));
                }
            }
            if (context.judgeElseStatement() != null)
            {
                obj += Visit(context.judgeElseStatement());
            }
            return obj;
        }

        public override object VisitJudgeBaseStatement([NotNull] XyParser.JudgeBaseStatementContext context)
        {
            var b = (Result)Visit(context.expression());
            var obj = $"if ( {b.text} ) {Wrap} {BlockLeft} {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += $"{BlockRight} {Wrap}";
            return obj;
        }

        public override object VisitJudgeElseStatement([NotNull] XyParser.JudgeElseStatementContext context)
        {
            var obj = $"else {Wrap} {BlockLeft} {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += $"{BlockRight}{Wrap}";
            return obj;
        }

        public override object VisitCheckStatement([NotNull] XyParser.CheckStatementContext context)
        {
            var obj = "";
            if (context.expression() != null)
            {
                obj += $"try {BlockLeft} {Wrap}";
                obj += (Visit(context.expression()) as Result).text + Terminate;
            }
            else
            {
                var v = (variableExpression)Visit(context.variableExpression());
                if (v.type != null)
                {
                    obj += $"{v.type} {v.id}{Terminate}";
                }
                obj += $"try {BlockLeft} {Wrap}";
                obj += $"{v.id} = {v.expr}{Terminate}";
            }

            obj += BlockRight + Wrap;
            if (context.checkErrorStatement() != null)
            {
                obj += Visit(context.checkErrorStatement()) + Terminate + Wrap;
            }
            else
            {
                var id = (Visit(context.id()) as Result).text;
                foreach (var item in stackHandle)
                {
                    if (item.id == id)
                    {
                        obj += $"catch {item.param}";
                        obj += $"{Wrap}{{{item.text}}}{Terminate}{Wrap}";
                        break;
                    }
                }
            }

            return obj;
        }

        private class variableExpression
        {
            public string type;
            public string id;
            public string expr;
        }

        public override object VisitVariableExpression([NotNull] XyParser.VariableExpressionContext context)
        {
            var v = new variableExpression();
            if (context.type() != null)
            {
                v.type = (string)Visit(context.type());
            }

            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            v.id = r1.text;
            v.expr = r2.text;
            return v;
        }

        public override object VisitCheckErrorStatement([NotNull] XyParser.CheckErrorStatementContext context)
        {
            var obj = "";
            var ID = "ex";
            if (context.id() != null)
            {
                ID = (Visit(context.id()) as Result).text;
            }

            var Type = "Exception";
            if (context.type() != null)
            {
                Type = (string)Visit(context.type());
            }

            obj += $"catch( {Type} {ID} ){Wrap + BlockLeft + Wrap} ";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += BlockRight;
            return obj;
        }

        public override object VisitReportStatement([NotNull] XyParser.ReportStatementContext context)
        {
            var obj = "";
            if (context.expression() != null)
            {
                var r = (Result)Visit(context.expression());
                obj += r.text;
            }
            return $"throw {obj + Terminate + Wrap}";
        }

        public override object VisitCheckDeferStatement([NotNull] XyParser.CheckDeferStatementContext context)
        {
            var obj = "";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            return obj;
        }

        private class Handle
        {
            public string id;
            public string param;
            public string text;
        }

        public override object VisitHandleStatement([NotNull] XyParser.HandleStatementContext context)
        {
            var res = new Handle
            {
                id = (Visit(context.id()) as Result).text,
                param = (Visit(context.parameterClauseIn()) as string)
            };
            foreach (var item in context.functionSupportStatement())
            {
                res.text += (string)Visit(item);
            }
            return res;
        }

        public override object VisitCallHandleStatement([NotNull] XyParser.CallHandleStatementContext context)
        {
            var id = (Visit(context.id()) as Result).text;
            var obj = "";
            foreach (var item in stackHandle)
            {
                if (item.id == id)
                {
                    obj = item.text;
                    break;
                }
            }
            if (obj == "")
            {
                throw new System.Exception($"did not find handle {id}");
            }

            return obj;
        }

        public override object VisitLinq([NotNull] XyParser.LinqContext context)
        {
            var r = new Result
            {
                data = "var"
            };
            r.text += "from " + ((Result)Visit(context.expression(0))).text + " ";
            foreach (var item in context.linqItem())
            {
                r.text += (string)Visit(item) + " ";
            }
            r.text += context.k.Text + " " + ((Result)Visit(context.expression(1))).text;
            return r;
        }

        public override object VisitLinqItem([NotNull] XyParser.LinqItemContext context)
        {
            if (context.expression() != null)
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
