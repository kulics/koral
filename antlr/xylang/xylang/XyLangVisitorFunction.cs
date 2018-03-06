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
        public override object VisitFunctionStatement([NotNull] XyParser.FunctionStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = "";
            // 异步
            if(context.t.Type == XyParser.FunctionAsync)
            {
                var pout = (string)Visit(context.parameterClauseOut());
                if(pout != "void")
                {
                    pout = "Task<" + pout + ">";
                }
                else
                {
                    pout = "Task";
                }
                obj += " async " + pout + " " + id.text;
            }
            else
            {
                obj += Visit(context.parameterClauseOut()) + " " + id.text;
            }
            // 泛型
            if(context.templateDefine() != null)
            {
                obj += Visit(context.templateDefine());
            }
            obj += Visit(context.parameterClauseIn()) + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.functionSupportStatement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitReturnStatement([NotNull] XyParser.ReturnStatementContext context)
        {
            var r = (Result)Visit(context.expressionList());
            return "return (" + r.text + ")" + context.Terminate().GetText() + Wrap;
        }

        public override object VisitTuple([NotNull] XyParser.TupleContext context)
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
            var result = new Result { data = "var", text = obj };
            return result;
        }

        public override object VisitParameterClauseIn([NotNull] XyParser.ParameterClauseInContext context)
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

        public override object VisitParameterClauseOut([NotNull] XyParser.ParameterClauseOutContext context)
        {
            var obj = "";
            if(context.parameter().Length == 0)
            {
                obj += "void";
            }
            else if(context.parameter().Length == 1)
            {
                obj += Visit(context.parameter(0).type());
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

        public override object VisitParameter([NotNull] XyParser.ParameterContext context)
        {
            var id = (Result)Visit(context.id());
            return Visit(context.type()) + " " + id.text;
        }

        public override object VisitCheckStatement([NotNull] XyParser.CheckStatementContext context)
        {
            var obj = "";
            obj += "try " + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.functionSupportStatement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + Wrap;
            obj += Visit(context.checkErrorStatement()) + Wrap;
            return obj;
        }

        public override object VisitCheckErrorStatement([NotNull] XyParser.CheckErrorStatementContext context)
        {
            var obj = "";
            var ID = (Result)Visit(context.id());
            obj += "catch(Exception " + ID.text + ")" + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.functionSupportStatement())
            {
                obj += Visit(item);
            }
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
    }
}
