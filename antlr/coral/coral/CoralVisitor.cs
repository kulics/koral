using Antlr4.Runtime.Misc;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace coral
{
    class CoralVisitor : CoralBaseVisitor<object>
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

        public override object VisitExportStatement([NotNull] CoralParser.ExportStatementContext context)
        {
            var obj = "namespace " + Visit(context.nameSpace()) + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.statement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitImportStatement([NotNull] CoralParser.ImportStatementContext context)
        {
            var obj = "";

            foreach(var item in context.nameSpaceStatement())
            {
                obj += "using " + Visit(item) + Wrap;
            }
            return obj;
        }

        public override object VisitNameSpaceStatement([NotNull] CoralParser.NameSpaceStatementContext context)
        {
            var obj = Visit(context.nameSpace()) + context.Terminate().GetText();
            return obj;
        }

        public override object VisitNameSpace([NotNull] CoralParser.NameSpaceContext context)
        {
            var obj = "";
            for(int i = 0; i < context.id().Length; i++)
            {
                var id = (Result)Visit(context.id(i));
                if(i == 0)
                {
                    obj += "" + id.text;
                }
                else
                {
                    obj += "." + id.text;
                }
            }
            return obj;
        }

        public override object VisitPackageStatement([NotNull] CoralParser.PackageStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = id.permission + " class " + id.text + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.statement())
            {
                if(item.GetChild(0).GetType() == typeof(CoralParser.FunctionMainStatementContext))
                {
                    obj += "static void Main(string[] args)" + Wrap + context.BlockLeft().GetText() + Wrap;
                    obj += "new " + id.text + "().init(args);" + Wrap;
                    obj += context.BlockRight().GetText() + Wrap;
                }
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitFunctionMainStatement([NotNull] CoralParser.FunctionMainStatementContext context)
        {
            var obj = "void init(string[] args)" + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.statement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitFunctionStatement([NotNull] CoralParser.FunctionStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = id.permission + Visit(context.parameterClauseOut()) + id.text
                + Visit(context.parameterClauseIn()) + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.statement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitReturnStatement([NotNull] CoralParser.ReturnStatementContext context)
        {
            var r = (Result)Visit(context.expressionList());
            return "return " + r.text + context.Terminate().GetText() + Wrap;
        }

        public override object VisitTuple([NotNull] CoralParser.TupleContext context)
        {
            var obj = "(";
            for(int i = 0; i < context.expression().Length; i++)
            {
                var r = (Result)Visit(context.expression(i));
                if(i == 0)
                {
                    obj += r.text;
                }
                else
                {
                    obj += ", " + r.text;
                }
            }
            obj += ")";
            return obj;
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

        public override object VisitParameterClauseIn([NotNull] CoralParser.ParameterClauseInContext context)
        {
            var obj = "( ";

            for(int i = 0; i < context.parameter().Length; i++)
            {
                if(i == 0)
                {
                    obj += Visit(context.parameter(0));
                }
                else
                {
                    obj += ", " + Visit(context.parameter(i));
                }
            }
            obj += " )";
            return obj;
        }

        public override object VisitParameterClauseOut([NotNull] CoralParser.ParameterClauseOutContext context)
        {
            var obj = "";
            if(context.parameter().Length == 0)
            {
                obj += "void";
            }
            else if(context.parameter().Length == 1)
            {
                obj += Visit(context.parameter(0).basicType());
            }
            if(context.parameter().Length > 1)
            {
                obj += "( ";
                for(int i = 0; i < context.parameter().Length; i++)
                {
                    if(i == 0)
                    {
                        obj += Visit(context.parameter(0));
                    }
                    else
                    {
                        obj += ", " + Visit(context.parameter(i));
                    }
                }
                obj += " )";
            }
            return obj;
        }

        public override object VisitParameter([NotNull] CoralParser.ParameterContext context)
        {
            var id = (Result)Visit(context.id());
            return Visit(context.basicType()) + id.text;
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
            foreach(var item in context.statement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitLoopInfiniteStatement([NotNull] CoralParser.LoopInfiniteStatementContext context)
        {
            var obj = "while (true)" + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.statement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitJudgeWithElseStatement([NotNull] CoralParser.JudgeWithElseStatementContext context)
        {
            var obj = Visit(context.judgeBaseStatement()) + Wrap + " else " + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.statement())
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
            foreach(var item in context.statement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText();
            return obj;
        }

        public override object VisitInvariableStatement([NotNull] CoralParser.InvariableStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = r2.data + " " + r1.text + " = " + r2.text + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitAssignStatement([NotNull] CoralParser.AssignStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = r1.text + " = " + r2.text + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitExpressionStatement([NotNull] CoralParser.ExpressionStatementContext context)
        {
            var r = (Result)Visit(context.expression());
            return r.text + context.Terminate().GetText() + Wrap;
        }

        public override object VisitExpression([NotNull] CoralParser.ExpressionContext context)
        {
            var count = context.ChildCount;
            var r = new Result();
            if(count == 2)
            {
                r.data = "var";
                var id = (Result)Visit(context.id());
                r.text = id.text + Visit(context.tuple());
            }
            else if(count == 3)
            {
                if(context.GetChild(1).GetType() == typeof(CoralParser.CallContext))
                {
                    r.data = "double";
                }
                else if(context.GetChild(1).GetType() == typeof(CoralParser.JudgeContext))
                {
                    // todo 如果左右不是bool类型值，报错
                    r.data = "bool";
                }
                else if(context.GetChild(1).GetType() == typeof(CoralParser.AddContext))
                {
                    // todo 如果左右不是number或text类型值，报错
                    r.data = "double";
                }
                else if(context.GetChild(1).GetType() == typeof(CoralParser.MulContext))
                {
                    // todo 如果左右不是number类型值，报错
                    r.data = "double";
                }
                else if(context.GetChild(1).GetType() == typeof(CoralParser.WaveContext))
                {
                    r.data = "var";
                    r.text = "new " + Visit(context.GetChild(0)) + Visit(context.GetChild(2));
                    return r;
                }
                var e1 = (Result)Visit(context.GetChild(0));
                var op = Visit(context.GetChild(1));
                var e2 = (Result)Visit(context.GetChild(2));
                r.text = e1.text + op + e2.text;
            }
            else if(count == 1)
            {
                r = (Result)Visit(context.GetChild(0));
            }
            return r;
        }

        public override object VisitCall([NotNull] CoralParser.CallContext context)
        {
            return context.op.Text;
        }

        public override object VisitWave([NotNull] CoralParser.WaveContext context)
        {
            return context.op.Text;
        }

        public override object VisitJudge([NotNull] CoralParser.JudgeContext context)
        {
            return context.op.Text;
        }

        public override object VisitAdd([NotNull] CoralParser.AddContext context)
        {
            return context.op.Text;
        }

        public override object VisitMul([NotNull] CoralParser.MulContext context)
        {
            return context.op.Text;
        }

        public override object VisitPrimaryExpression([NotNull] CoralParser.PrimaryExpressionContext context)
        {
            if(context.ChildCount == 1)
            {
                var c = context.GetChild(0);
                if(c is CoralParser.DataStatementContext)
                {
                    return Visit(context.dataStatement());
                }
                else if(c is CoralParser.IdContext)
                {
                    return Visit(context.id());
                }
                else if(context.t.Type == CoralParser.Self)
                {
                    return new Result { text = "this", data = "var" };
                }
            }
            var r = (Result)Visit(context.expression());
            return new Result { text = "(" + r.text + ")", data = r.data };
        }

        public override object VisitId([NotNull] CoralParser.IdContext context)
        {
            if(context.op.Type == CoralParser.IDPublic)
            {
                return new Result { text = "@" + context.op.Text, data = "double", permission = "public"};
            }
            else
            {
                return new Result { text = "@" + context.op.Text, data = "double", permission = "private" };
            }
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

        public override object VisitDataStatement([NotNull] CoralParser.DataStatementContext context)
        {
            var r = new Result();
            if(context.t.Type == CoralParser.Number)
            {
                r.data = "double";
                r.text = context.Number().GetText();
            }
            else if(context.t.Type == CoralParser.Text)
            {
                r.data = "string";
                r.text = context.Text().GetText();
            }
            else if(context.t.Type == CoralParser.True)
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

        public override object VisitBasicType([NotNull] CoralParser.BasicTypeContext context)
        {
            var obj = "";
            switch(context.t.Type)
            {
                case CoralParser.TypeNumber:
                    obj = "double";
                    break;
                case CoralParser.TypeText:
                    obj = "string";
                    break;
                case CoralParser.TypeBool:
                    obj = "bool";
                    break;
                default:
                    obj = "object";
                    break;
            }
            return obj;
        }


        //public override object VisitMulDiv([NotNull] CoralParser.MulDivContext context)
        //{
        //    //return base.VisitMulDiv(context);
        //    return VisitAtom(context.atom(0)) + "mul and div";
        //}

        //public override object VisitAtom([NotNull] CoralParser.AtomContext context)
        //{

        //    return "hello world";
        //}

        //public override object VisitPrint([NotNull] CoralParser.PrintContext context)
        //{
        //    var obj = VisitExpr(context.expr());
        //    return obj;
        //}

        //public override object VisitId([NotNull] CoralParser.IdContext context)
        //{
        //    return base.VisitId(context);
        //}

        //public override object VisitMulDiv([NotNull] CoralParser.MulDivContext context)
        //{
        //    double left = Convert.ToDouble(Visit(context.primary(0)));
        //    double right = Convert.ToDouble(Visit(context.primary(1)));

        //    object obj = new object();
        //    if (context.op.Type == CoralParser.Mul)
        //    {
        //        obj = left * right;
        //    }
        //    else if (context.op.Type == CoralParser.Div)
        //    {
        //        if (right == 0)
        //        {
        //            throw new Exception("Cannot divide by zero.");
        //        }
        //        obj = left / right;
        //    }

        //    return obj;
        //}

        //public override object VisitAddSub([NotNull] CoralParser.AddSubContext context)
        //{
        //    double left = Convert.ToDouble(Visit(context.mulDiv(0)));
        //    double right = Convert.ToDouble(Visit(context.mulDiv(1)));

        //    object obj = new object();
        //    if (context.op.Type == CoralParser.Add)
        //    {
        //        obj = left + right;
        //    }
        //    else if (context.op.Type == CoralParser.Sub)
        //    {
        //        obj = left - right;
        //    }
        //    return obj;
        //}
    }
}
