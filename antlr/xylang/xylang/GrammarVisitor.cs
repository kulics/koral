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
            var obj = "namespace " + context.ID().GetText() + @"
" + context.BlockLeft().GetText() + @"
";
            foreach (var item in context.statement())
            {
                obj += VisitStatement(item);
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + @"
";
            return obj;
        }

        public override object VisitImportStatement([NotNull] GrammarParser.ImportStatementContext context)
        {
            var obj = "";

            foreach (var item in context.nameSpaceStatement())
            {
                obj += "using " + VisitNameSpaceStatement(item) + @"
";
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
            var obj = "class " + context.ID().GetText() + @"
" + context.BlockLeft().GetText() + @"
";
            foreach (var item in context.statement())
            {
                obj += VisitStatement(item);
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + @"
";
            return obj;
        }

        public override object VisitFunctionStatement([NotNull] GrammarParser.FunctionStatementContext context)
        {
            var obj = "void " + context.ID().GetText() + "(double " + context.basicType(0).GetText() + ")" + @"
" + context.BlockLeft().GetText() + @"
";
            foreach (var item in context.statement())
            {
                obj += VisitStatement(item);
            }
            obj += context.BlockRight().GetText() + @"
";
            return obj;
        }

        public override object VisitInvariableStatement([NotNull] GrammarParser.InvariableStatementContext context)
        {
            var obj = "double " + context.ID().GetText() + " = " + context.Number().GetText() + context.Terminate().GetText() + @"
";
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

        //public override object VisitPrimary([NotNull] GrammarParser.PrimaryContext context)
        //{
        //    //if (context.ChildCount == 1)
        //    //{
        //    //var c = context.GetChild(0);
        //    //if (c is TinyScriptParser.VariableExpressionContext)
        //    //{
        //    //    return VisitVariableExpression(context.variableExpression());
        //    //}
        //    //var num = context.numericLiteral().GetText().Replace("_", "");
        //    //var b = OpBuilder.GetOpBuilder(typeof(decimal), context, _builder);
        //    //b.LoadNum(num);
        //    //return typeof(decimal);
        //    //}
        //    //return VisitExpr(context.expr());
        //    var obj = context.GetText();
        //    return obj;
        //}

        //public override object VisitNumber([NotNull] GrammarParser.NumberContext context)
        //{
        //    var obj = context.GetText();
        //    return obj;
        //}
    }
}

