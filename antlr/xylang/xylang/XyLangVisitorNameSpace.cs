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
            var obj = "";
            obj += "namespace " + Visit(context.nameSpace()) + Wrap + context.BlockLeft().GetText() + Wrap;

            foreach(var item in context.exportSupportStatement())
            {
                obj += Visit(item);
            }
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
            if(context.callEllipsis() != null)
            {
                var ns = (string)Visit(context.nameSpace());
                obj += "using static " + ns;
                if(context.id() != null)
                {
                    var r = (Result)Visit(context.id());

                    obj += "." + r.text;
                }

                obj += context.Terminate().GetText();
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

        public override object VisitNameSpaceItem([NotNull] XyParser.NameSpaceItemContext context)
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

        public override object VisitName([NotNull] XyParser.NameContext context)
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

        public override object VisitNspackageStatement([NotNull] XyParser.NspackageStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = "";
            foreach(var item in context.nspackageSupportStatement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            var header = "";
            if(context.annotation() != null)
            {
                header += Visit(context.annotation());
            }
            header += id.permission + " static partial class " + id.text;
            // 泛型
            if(context.templateDefine() != null)
            {
                header += Visit(context.templateDefine());
            }

            header += Wrap + context.BlockLeft().GetText() + Wrap;
            obj = header + obj;
            return obj;
        }

        public override object VisitEnumStatement([NotNull] XyParser.EnumStatementContext context)
        {
            var obj = "";
            var id = (Result)Visit(context.id());
            var header = "";
            if(context.annotation() != null)
            {
                header += Visit(context.annotation());
            }
            header += id.permission + " enum " + id.text;
            header += Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.enumSupportStatement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            obj = header + obj;
            return obj;
        }

        public override object VisitEnumSupportStatement([NotNull] XyParser.EnumSupportStatementContext context)
        {
            var id = (Result)Visit(context.id());
            if(context.Integer() != null)
            {
                var op = "";
                if(context.add() != null)
                {
                    op = (string)Visit(context.add());
                }
                id.text += " = " + op + context.Integer().GetText();
            }
            return id.text + ",";
        }

        public override object VisitFunctionMainStatement([NotNull] XyParser.FunctionMainStatementContext context)
        {
            var obj = "";
            obj += "static class XyLangMainFunctionEnter " + Wrap + context.BlockLeft().GetText() + Wrap;
            obj += "static void Main(string[] args)" + Wrap + context.BlockLeft().GetText() + Wrap;
            obj += "MainAsync(args).GetAwaiter().GetResult();" + Wrap + context.BlockRight().GetText() + Wrap;
            obj += "static async Task MainAsync(string[] args)" + Wrap + context.BlockLeft().GetText() + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += context.BlockRight().GetText() + Wrap;
            obj += context.BlockRight().GetText() + Wrap;

            return obj;
        }

        public override object VisitNspackageFunctionStatement([NotNull] XyParser.NspackageFunctionStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = "";
            if(context.annotation() != null)
            {
                obj += Visit(context.annotation());
            }
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

        public override object VisitNspackageInvariableStatement([NotNull] XyParser.NspackageInvariableStatementContext context)
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

        public override object VisitNspackageVariableStatement([NotNull] XyParser.NspackageVariableStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = "";
            if(context.annotation() != null)
            {
                obj += Visit(context.annotation());
            }
            obj += " private static " + r2.data + " " + r1.text + " = " + r2.text + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitNspackageControlEmptyStatement([NotNull] XyParser.NspackageControlEmptyStatementContext context)
        {
            var obj = "";
            if(context.annotation() != null)
            {
                obj += Visit(context.annotation());
            }
            var id = (Result)Visit(context.id());
            var type = (string)Visit(context.type());
            obj += id.permission + " static " + type + " " + id.text + "{get;set;}" + Wrap;
            return obj;
        }

        public override object VisitNspackageControlStatement([NotNull] XyParser.NspackageControlStatementContext context)
        {
            var obj = "";
            if(context.annotation() != null)
            {
                obj += Visit(context.annotation());
            }
            var id = (Result)Visit(context.id());
            var type = (string)Visit(context.type());
            obj += id.permission + " static " + type + " " + id.text + "{";
            foreach(var item in context.nspackageControlSubStatement())
            {
                obj += Visit(item);
            }
            obj += "}" + Wrap;
            return obj;
        }

        public override object VisitNspackageControlSubStatement([NotNull] XyParser.NspackageControlSubStatementContext context)
        {
            var obj = "";
            var id = "";
            id = GetControlSub(context.id().GetText());
            obj += id + "{";
            foreach(var item in context.functionSupportStatement())
            {
                obj += Visit(item);
            }
            obj += "}" + Wrap;
            return obj;
        }

        public string GetControlSub(string id)
        {
            switch(id)
            {
                case "get":
                    id = " get ";
                    break;
                case "set":
                    id = " set ";
                    break;
                case "_get":
                    id = " private get ";
                    break;
                case "_set":
                    id = " private set ";
                    break;
                case "add":
                    id = " add ";
                    break;
                case "remove":
                    id = " remove ";
                    break;
                default:
                    break;
            }
            return id;
        }
    }
}
