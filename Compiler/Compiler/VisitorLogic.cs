using Antlr4.Runtime.Misc;
using static Compiler.XsParser;

namespace Compiler {
    internal partial class Visitor {
        public class Iterator {
            public Result Begin;
            public Result End;
            public Result Step;
            public string Order = t;
            public string Attach = f;
        }

        public override object VisitIteratorStatement([NotNull] IteratorStatementContext context) {
            var it = new Iterator();
            if (context.op.Text == ">=" || context.op.Text == "<=") {
                it.Attach = t;
            }
            if (context.op.Text == ">" || context.op.Text == ">=") {
                it.Order = f;
            }
            if (context.expression().Length == 2) {
                it.Begin = (Result)Visit(context.expression(0));
                it.End = (Result)Visit(context.expression(1));
                it.Step = new Result { data = i32, text = "1" };
            } else {
                it.Begin = (Result)Visit(context.expression(0));
                it.End = (Result)Visit(context.expression(1));
                it.Step = (Result)Visit(context.expression(2));
            }
            return it;
        }

        public override object VisitLoopStatement([NotNull] LoopStatementContext context) {
            var obj = "";
            var id = "ea";
            if (context.id() != null) {
                id = ((Result)Visit(context.id())).text;
            }
            var it = (Iterator)Visit(context.iteratorStatement());

            obj += $"foreach (var {id} in Range({it.Begin.text},{it.End.text},{it.Step.text},{it.Order},{it.Attach}))";

            obj += $"{Wrap} {BlockLeft} {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += $"{BlockRight} {Terminate} {Wrap}";
            return obj;
        }

        public override object VisitLoopInfiniteStatement([NotNull] LoopInfiniteStatementContext context) {
            var obj = $"for (;;) {Wrap} {BlockLeft} {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += $"{BlockRight} {Terminate} {Wrap}";
            return obj;
        }

        public override object VisitLoopEachStatement([NotNull] LoopEachStatementContext context) {
            var obj = "";
            var arr = (Visit(context.expression()) as Result);
            var target = arr.text;
            var id = "ea";
            if (context.id().Length == 2) {
                target = $"Range({target})";
                id = $"({((Result)Visit(context.id(0))).text},{((Result)Visit(context.id(1))).text})";
            } else if (context.id().Length == 1) {
                id = ((Result)Visit(context.id(0))).text;
            }

            obj += $"foreach (var {id} in {target})";
            obj += $"{Wrap} {BlockLeft} {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += $"{BlockRight} {Terminate} {Wrap}";
            return obj;
        }

        public override object VisitLoopCaseStatement([NotNull] LoopCaseStatementContext context) {
            var obj = "";
            var expr = (Result)Visit(context.expression());
            obj += $"for ( ;{expr.text} ;)";
            obj += $"{Wrap} {BlockLeft} {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += $"{BlockRight} {Terminate} {Wrap}";
            return obj;
        }

        public override object VisitLoopJumpStatement([NotNull] LoopJumpStatementContext context) {
            return $"break {Terminate} {Wrap}";
        }

        public override object VisitLoopContinueStatement([NotNull] LoopContinueStatementContext context) {
            return $"continue {Terminate} {Wrap}";
        }

        public override object VisitJudgeCaseStatement([NotNull] JudgeCaseStatementContext context) {
            var obj = "";
            var expr = (Result)Visit(context.expression());
            obj += $"switch ({expr.text}) {Wrap} {{ {Wrap}";
            foreach (var item in context.caseStatement()) {
                var r = (string)Visit(item);
                obj += r + Wrap;
            }
            obj += $"}} {Wrap}";
            return obj;
        }

        public override object VisitCaseDefaultStatement([NotNull] CaseDefaultStatementContext context) {
            var obj = "";
            obj += $"default:{{ {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += "}break;";
            return obj;
        }

        public override object VisitCaseExprStatement([NotNull] CaseExprStatementContext context) {
            var obj = "";
            if (context.type() is null) {
                var expr = (Result)Visit(context.expression());
                obj += $"case {expr.text} :{Wrap}";
            } else {
                var id = "it";
                if (context.id() != null) {
                    id = ((Result)Visit(context.id())).text;
                }
                var type = (string)Visit(context.type());
                obj += $"case {type} {id} :{Wrap}";
            }

            obj += $"{{ {ProcessFunctionSupport(context.functionSupportStatement())} }}";
            obj += "break;";
            return obj;
        }

        public override object VisitCaseStatement([NotNull] CaseStatementContext context) {
            var obj = (string)Visit(context.GetChild(0));
            return obj;
        }

        public override object VisitJudgeStatement([NotNull] JudgeStatementContext context) {
            var obj = "";
            obj += Visit(context.judgeIfStatement());
            foreach (var it in context.judgeElseIfStatement()) {
                obj += Visit(it);
            }
            if (context.judgeElseStatement() != null) {
                obj += Visit(context.judgeElseStatement());
            }
            return obj;
        }

        public override object VisitJudgeIfStatement([NotNull] JudgeIfStatementContext context) {
            var b = (Result)Visit(context.expression());
            var obj = $"if ( {b.text} ) {Wrap} {BlockLeft} {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += $"{BlockRight} {Wrap}";
            return obj;
        }

        public override object VisitJudgeElseIfStatement([NotNull] JudgeElseIfStatementContext context) {
            var b = (Result)Visit(context.expression());
            var obj = $"else if ( {b.text} ) {Wrap} {BlockLeft} {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += $"{BlockRight} {Wrap}";
            return obj;
        }

        public override object VisitJudgeElseStatement([NotNull] JudgeElseStatementContext context) {
            var obj = $"else {Wrap} {BlockLeft} {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += $"{BlockRight}{Wrap}";
            return obj;
        }

        public override object VisitCheckStatement([NotNull] CheckStatementContext context) {
            if (context.checkErrorStatement().Length == 0 && context.checkFinallyStatment() == null) {
                var obj = "using (";
                obj += Visit(context.usingExpression()) + ")" + BlockLeft + Wrap;
                obj += ProcessFunctionSupport(context.functionSupportStatement());
                obj += BlockRight + Wrap;
                return obj;
            } else {
                var obj = $"try {BlockLeft} {Wrap}";
                obj += ProcessFunctionSupport(context.functionSupportStatement());
                obj += BlockRight + Wrap;
                foreach (var item in context.checkErrorStatement()) {
                    obj += Visit(item) + Wrap;
                }

                if (context.checkFinallyStatment() != null) {
                    obj += Visit(context.checkFinallyStatment());
                }
                if (context.usingExpression() != null) {
                    obj = $"using ({ Visit(context.usingExpression())}) {BlockLeft} {Wrap} {obj} ";
                    obj += BlockRight + Wrap;
                }
                return obj;
            }
        }

        public override object VisitUsingExpression([NotNull] UsingExpressionContext context) {
            var obj = "";
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            if (context.type() != null) {
                var Type = (string)Visit(context.type());
                obj = $"{Type} {r1.text} = {r2.text}";
            } else {
                obj = $"var {r1.text} = {r2.text}";
            }
            return obj;
        }

        public override object VisitCheckErrorStatement([NotNull] CheckErrorStatementContext context) {
            var obj = "";
            var ID = "ex";
            if (context.id() != null) {
                ID = (Visit(context.id()) as Result).text;
            }

            var Type = "Exception";
            if (context.type() != null) {
                Type = (string)Visit(context.type());
            }

            obj += $"catch( {Type} {ID} ){Wrap + BlockLeft + Wrap} ";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += BlockRight;
            return obj;
        }

        public override object VisitCheckFinallyStatment([NotNull] CheckFinallyStatmentContext context) {
            var obj = $"finally {Wrap} {BlockLeft} {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += $"{BlockRight}{Wrap}";
            return obj;
        }

        public override object VisitReportStatement([NotNull] ReportStatementContext context) {
            var obj = "";
            if (context.expression() != null) {
                var r = (Result)Visit(context.expression());
                obj += r.text;
            }
            return $"throw {obj + Terminate + Wrap}";
        }

        public override object VisitLinq([NotNull] LinqContext context) {
            var r = new Result {
                data = "var"
            };
            r.text += "from " + ((Result)Visit(context.expression(0))).text + " ";
            foreach (var item in context.linqItem()) {
                r.text += (string)Visit(item) + " ";
            }
            r.text += context.k.Text + " " + ((Result)Visit(context.expression(1))).text;
            return r;
        }

        public override object VisitLinqItem([NotNull] LinqItemContext context) {
            if (context.expression() != null) {
                return ((Result)Visit(context.expression())).text;
            }
            return (string)Visit(context.linqBodyKeyword());
        }

        public override object VisitLinqKeyword([NotNull] LinqKeywordContext context) {
            return Visit(context.GetChild(0));
        }

        public override object VisitLinqHeadKeyword([NotNull] LinqHeadKeywordContext context) {
            return context.k.Text;
        }

        public override object VisitLinqBodyKeyword([NotNull] LinqBodyKeywordContext context) {
            return context.k.Text;
        }
    }
}
