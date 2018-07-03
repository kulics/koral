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
            if(context.t.Type == XyParser.FunctionSub)
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
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitReturnStatement([NotNull] XyParser.ReturnStatementContext context)
        {
            var r = (Result)Visit(context.tuple());
            if(r.text == "()")
            {
                r.text = "";
            }
            return "return " + r.text + "" + context.Terminate().GetText() + Wrap;
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

            var lastType = "";
            var temp = new List<string>();
            for(int i = context.parameter().Length - 1; i >= 0; i--)
            {
                Parameter p = (Parameter)Visit(context.parameter(i));
                if (p.type != "")
                {
                    lastType = p.type;
                }
                else
                {
                    p.type = lastType;
                }

                temp.Add($"{p.annotation} {p.type} {p.id}");
            }
            for (int i = temp.Count - 1; i >= 0; i--)
            {
                if (i == temp.Count - 1)
                {
                    obj += temp[i];
                }
                else
                {
                    obj += $", {temp[i]}";
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
                Parameter p = (Parameter)Visit(context.parameter(0));
                obj += p.type;
            }
            if(context.parameter().Length > 1)
            {
                obj += "( ";
                var lastType = "";
                var temp = new List<string>();
                for (int i = context.parameter().Length - 1; i >= 0; i--)
                {
                    Parameter p = (Parameter)Visit(context.parameter(i));
                    if (p.type != "")
                    {
                        lastType = p.type;
                    }
                    else
                    {
                        p.type = lastType;
                    }
                    temp.Add($"{p.annotation} {p.type} {p.id}");
                }
                for (int i = temp.Count - 1; i >= 0; i--)
                {
                    if (i == temp.Count - 1)
                    {
                        obj += temp[i];
                    }
                    else
                    {
                        obj += $", {temp[i]}";
                    }
                }
                obj += " )";
            }
            return obj;
        }

        public class Parameter
        {
            public string id { get; set; }
            public string type { get; set; } 
            public string annotation { get; set; }
        }

        public override object VisitParameter([NotNull] XyParser.ParameterContext context)
        {
            var p = new Parameter();
            p.id = ((Result)Visit(context.id())).text;
            if(context.annotation() != null)
            {
                p.annotation = (string)Visit(context.annotation());
            }
            if (context.type() != null)
            {
                p.type = (string)Visit(context.type());
            }

            return p;
        }


        public string ProcessFunctionSupport(XyParser.FunctionSupportStatementContext[] items)
        {
            var obj = "";
            var content = "";
            var defer = new List<string>();
            foreach(var item in items)
            {
                if(item.GetChild(0) is XyParser.CheckDeferStatementContext)
                {
                    defer.Add((string)Visit(item));
                    content += "try" + Wrap + "{";
                }
                else
                {
                    content += Visit(item);
                }
            }
            if(defer.Count > 0)
            {
                for(int i = defer.Count - 1; i >= 0; i--)
                {
                    content += "}" + Wrap + "finally" + Wrap + "{" + defer[i] + "}";
                }
            }
            obj += content;
            return obj;
        }
    }
}
