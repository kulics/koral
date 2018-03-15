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
        public override object VisitExportStatement([NotNull] XyParser.ExportStatementContext context)
        {
            var nameSpace = (string)Visit(context.nameSpace());
            if(nameSpace.LastIndexOf(".") >= 0)
            {
                nameSpace = nameSpace.Substring(nameSpace.LastIndexOf("."));
            }
            var obj = "";
            obj += "namespace " + Visit(context.nameSpace()) + Wrap + context.BlockLeft().GetText() + Wrap;

            var content = "";
            foreach(var item in context.exportSupportStatement())
            {
                if(item.GetChild(0) is XyParser.ImportStatementContext)
                {
                    obj += Visit(item);
                }
                else
                {
                    content += Visit(item);
                }
            }
            obj += "public static partial class " + nameSpace + Wrap + context.BlockLeft().GetText() + Wrap;
            obj += content;
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitImportStatement([NotNull] XyParser.ImportStatementContext context)
        {
            var obj = "";

            foreach(var item in context.nameSpaceStatement())
            {
                obj += Visit(item) + Wrap;
            }
            return obj;
        }

        public override object VisitNameSpaceStatement([NotNull] XyParser.NameSpaceStatementContext context)
        {
            var obj = "";
            if(context.annotation() != null)
            {
                obj += Visit(context.annotation());
            }
            if(context.callNamespace() != null)
            {
                var ns = (string)Visit(context.nameSpace());
                obj += "using static " + ns;
                if(ns.LastIndexOf(".") >= 0)
                {
                    ns = ns.Substring(ns.LastIndexOf("."));
                }
                obj += "." + ns + context.Terminate().GetText();
            }
            else
            {
                obj += "using " + Visit(context.nameSpace()) + context.Terminate().GetText();
            }
            return obj;
        }

        public override object VisitNameSpace([NotNull] XyParser.NameSpaceContext context)
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

        public override object VisitFunctionMainStatement([NotNull] XyParser.FunctionMainStatementContext context)
        {
            var obj = "";

            obj += "static void Main(string[] args)" + Wrap + context.BlockLeft().GetText() + Wrap;
            obj += "MainAsync(args).GetAwaiter().GetResult();" + Wrap + context.BlockRight().GetText() + Wrap;
            obj += "static async Task MainAsync(string[] args)" + Wrap + context.BlockLeft().GetText() + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += context.BlockRight().GetText() + Wrap;

            return obj;
        }

        public override object VisitNamespaceFunctionStatement([NotNull] XyParser.NamespaceFunctionStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = "";
            if(context.annotation() != null)
            {
                obj += Visit(context.annotation());
            }
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
                obj += id.permission + " async static " + pout + " " + id.text;
            }
            else
            {
                obj += id.permission + " static " + Visit(context.parameterClauseOut()) + " " + id.text;
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

        public override object VisitNamespaceInvariableStatement([NotNull] XyParser.NamespaceInvariableStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = "";
            if(context.annotation() != null)
            {
                obj += Visit(context.annotation());
            }
            obj += r1.permission + " const " + r2.data + " " + r1.text + " = " + r2.text + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitNamespaceVariableStatement([NotNull] XyParser.NamespaceVariableStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = "";
            if(context.annotation() != null)
            {
                obj += Visit(context.annotation());
            }
            obj += r1.permission + " static " + r2.data + " " + r1.text + " {get;set;} = " + r2.text + context.Terminate().GetText() + Wrap;
            return obj;
        }
    }
}
