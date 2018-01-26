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

        public override object VisitProgram([NotNull] GrammarParser.ProgramContext context)
        {
            var list = context.statement();
            var result = "";
            foreach (var item in list)
            {
                result += VisitStatement(item);
            }
            return result;
        }

        public override object VisitExportStatement([NotNull] GrammarParser.ExportStatementContext context)
        {
            var obj = "namespace " + context.ID().GetText() + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach (var item in context.statement())
            {
                obj += VisitStatement(item);
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitImportStatement([NotNull] GrammarParser.ImportStatementContext context)
        {
            var obj = "";

            foreach (var item in context.nameSpaceStatement())
            {
                obj += "using " + VisitNameSpaceStatement(item) + Wrap;
            }
            return obj;
        }

        public override object VisitNameSpaceStatement([NotNull] GrammarParser.NameSpaceStatementContext context)
        {
            var obj = context.ID().GetText() + context.Terminate().GetText();
            return obj;
        }

        public override object VisitPackageStatement([NotNull] GrammarParser.PackageStatementContext context)
        {
            var obj = "class " + context.ID().GetText() + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach (var item in context.statement())
            {
                if (item.GetChild(0).GetType() == typeof(GrammarParser.FunctionMainStatementContext))
                {
                    obj += "static void Main(string[] args)" + Wrap + context.BlockLeft().GetText() + Wrap;
                    obj += "new " + context.ID().GetText() + "().init(args);" + Wrap;
                    obj += context.BlockRight().GetText() + Wrap;
                }
                obj += VisitStatement(item);
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitFunctionMainStatement([NotNull] GrammarParser.FunctionMainStatementContext context)
        {
            var obj = "void init(string[] args)" + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach (var item in context.statement())
            {
                obj += VisitStatement(item);
            }
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitFunctionStatement([NotNull] GrammarParser.FunctionStatementContext context)
        {
            var obj = "void " + context.ID().GetText() + VisitParameterClause(context.parameterClause()) + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach (var item in context.statement())
            {
                obj += VisitStatement(item);
            }
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitParameterClause([NotNull] GrammarParser.ParameterClauseContext context)
        {
            var obj = "( ";
            //if (context.parameterList().Length > 0)
            //{
            obj += VisitParameterList(context.parameterList());
            //}
            obj += " )";
            return obj;
        }

        public override object VisitParameterList([NotNull] GrammarParser.ParameterListContext context)
        {
            var obj = "";
            if (context.ChildCount > 0)
            {
                obj += VisitBasicType(context.basicType(0)) + " p";
            }
            return obj;
        }

        public override object VisitInvariableStatement([NotNull] GrammarParser.InvariableStatementContext context)
        {
            var r = (Result)VisitDataStatement(context.dataStatement());
            var obj = r.data + " " + context.ID().GetText() + " = " + r.text + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitLoopStatement([NotNull] GrammarParser.LoopStatementContext context)
        {
            var obj = "for (double i =" + context.Number(0).GetText() + "; i<" + context.Number(1).GetText() + ";i++)"
                + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach (var item in context.statement())
            {
                obj += VisitStatement(item);
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitJudgeWithElseStatement([NotNull] GrammarParser.JudgeWithElseStatementContext context)
        {
            var obj = VisitJudgeBaseStatement(context.judgeBaseStatement()) + Wrap + " else " + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach (var item in context.statement())
            {
                obj += VisitStatement(item);
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitJudgeStatement([NotNull] GrammarParser.JudgeStatementContext context)
        {
            var obj = VisitJudgeBaseStatement(context.judgeBaseStatement()) + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitJudgeBaseStatement([NotNull] GrammarParser.JudgeBaseStatementContext context)
        {
            var b = (Result)VisitBool(context.@bool());
            var obj = "if (" + b.text + ")" + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach (var item in context.statement())
            {
                obj += VisitStatement(item);
            }
            obj += context.BlockRight().GetText();
            return obj;
        }

        const string Wrap = "\r\n";

        public override object VisitPrintStatement([NotNull] GrammarParser.PrintStatementContext context)
        {
            var obj = "Console.WriteLine(" + context.Text().GetText() + ")" + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public class Result
        {
            public object data { get; set; }
            public string text { get; set; }
        }

        public override object VisitBool([NotNull] GrammarParser.BoolContext context)
        {
            var r = new Result();
            if (context.t.Type == GrammarParser.True)
            {
                r.data = "bool";
                r.text = context.True().GetText();
            }
            else if (context.t.Type == GrammarParser.False)
            {
                r.data = "bool";
                r.text = context.False().GetText();
            }
            return r;
        }

        public override object VisitDataStatement([NotNull] GrammarParser.DataStatementContext context)
        {
            var r = new Result();
            if (context.t.Type == GrammarParser.Number)
            {
                r.data = "double";
                r.text = context.Number().GetText();
            }
            else if (context.t.Type == GrammarParser.Text)
            {
                r.data = "string";
                r.text = context.Text().GetText();
            }
            else if (context.t.Type == GrammarParser.True)
            {
                r.data = "bool";
                r.text = context.True().GetText();
            }
            else if (context.t.Type == GrammarParser.False)
            {
                r.data = "bool";
                r.text = context.False().GetText();
            }
            return r;
        }

        public override object VisitBasicType([NotNull] GrammarParser.BasicTypeContext context)
        {
            var obj = "";
            switch (context.t.Type)
            {
                case GrammarParser.TypeNumber:
                    obj = "double";
                    break;
                case GrammarParser.TypeText:
                    obj = "string";
                    break;
                case GrammarParser.TypeBool:
                    obj = "bool";
                    break;
                default:
                    obj = "object";
                    break;
            }
            return obj;
        }


        //public override object VisitMulDiv([NotNull] GrammarParser.MulDivContext context)
        //{
        //    //return base.VisitMulDiv(context);
        //    return VisitAtom(context.atom(0)) + "mul and div";
        //}

        //public override object VisitAtom([NotNull] GrammarParser.AtomContext context)
        //{

        //    return "hello world";
        //}

        //public override object VisitPrint([NotNull] GrammarParser.PrintContext context)
        //{
        //    var obj = VisitExpr(context.expr());
        //    return obj;
        //}

        //public override object VisitId([NotNull] GrammarParser.IdContext context)
        //{
        //    return base.VisitId(context);
        //}

        //public override object VisitMulDiv([NotNull] GrammarParser.MulDivContext context)
        //{
        //    double left = Convert.ToDouble(Visit(context.primary(0)));
        //    double right = Convert.ToDouble(Visit(context.primary(1)));

        //    object obj = new object();
        //    if (context.op.Type == GrammarParser.Mul)
        //    {
        //        obj = left * right;
        //    }
        //    else if (context.op.Type == GrammarParser.Div)
        //    {
        //        if (right == 0)
        //        {
        //            throw new Exception("Cannot divide by zero.");
        //        }
        //        obj = left / right;
        //    }

        //    return obj;
        //}

        //public override object VisitAddSub([NotNull] GrammarParser.AddSubContext context)
        //{
        //    double left = Convert.ToDouble(Visit(context.mulDiv(0)));
        //    double right = Convert.ToDouble(Visit(context.mulDiv(1)));

        //    object obj = new object();
        //    if (context.op.Type == GrammarParser.Add)
        //    {
        //        obj = left + right;
        //    }
        //    else if (context.op.Type == GrammarParser.Sub)
        //    {
        //        obj = left - right;
        //    }
        //    return obj;
        //}
    }
}

