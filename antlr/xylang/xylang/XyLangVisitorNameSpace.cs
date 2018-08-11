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
            obj += $"namespace {Visit(context.nameSpace()) + Wrap + BlockLeft + Wrap}";

            foreach(var item in context.exportSupportStatement())
            {
                obj += Visit(item);
            }
            obj += BlockRight + Wrap;
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

                obj += Terminate;
            }
            else
            {
                obj += "using " + Visit(context.nameSpace()) + Terminate;
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
            obj += BlockRight + Terminate + Wrap;
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

            header += Wrap + BlockLeft + Wrap;
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
            header += Wrap + BlockLeft + Wrap;
            for(int i = 0; i < context.enumSupportStatement().Length; i++)
            {
                obj += Visit(context.enumSupportStatement(i));
            }
            obj += BlockRight + Terminate + Wrap;
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
            obj += $"static class XyLangMainFunctionEnter {Wrap + BlockLeft + Wrap} " +
                $"static void Main(string[] args) {Wrap + BlockLeft + Wrap} " +
                $"MainAsync(args).GetAwaiter().GetResult(); {Wrap + BlockRight + Wrap}" +
                $"static async Task MainAsync(string[] args) {Wrap + BlockLeft + Wrap}" +
                $"{ProcessFunctionSupport(context.functionSupportStatement())}" +
                $"{BlockRight + Wrap}{BlockRight + Wrap}";
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
            if(context.t.Type == XyParser.FlowRight)
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
            obj += Visit(context.parameterClauseIn()) + Wrap + BlockLeft + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += BlockRight + Wrap;
            return obj;
        }

        public override object VisitNspackageInvariableStatement([NotNull] XyParser.NspackageInvariableStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var typ = "";
            if (context.type() != null)
            {
                typ = (string)Visit(context.type());
            }
            else
            {
                typ = (string)r2.data;
            }

            var obj = "";
            if(context.annotation() != null)
            {
                obj += Visit(context.annotation());
            }
            if (r2.text.StartsWith('$') || r2.text.Substring(0,3) == ("new"))
            {
                obj += $"{r1.permission} readonly static {typ} {r1.text} = {r2.text} {Terminate} {Wrap}";
            }
            else
            {
                obj += $"{r1.permission} const {typ} {r1.text} = {r2.text} {Terminate} {Wrap}";
            }

            return obj;
        }

        public override object VisitNspackageVariableStatement([NotNull] XyParser.NspackageVariableStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var typ = "";
            if (context.type() != null)
            {
                typ = (string)Visit(context.type());
            }
            else if (context.expression().Length == 2)
            {
                var r2 = (Result)Visit(context.expression(1));
                typ = (string)r2.data;
            }
            var obj = "";
            if(context.annotation() != null)
            {
                obj += Visit(context.annotation());
            }
            if (context.nspackageControlSubStatement().Length >0)
            {
                obj += $"{r1.permission} static {typ} {r1.text} {{";
                foreach (var item in context.nspackageControlSubStatement())
                {
                    obj += Visit(item);
                }
                obj += $"}} {Wrap}";
            }
            else
            {
                obj += $"{r1.permission} static {typ} {r1.text} {{ get;set; }} {Wrap}";
            }
            if (context.expression().Length == 2)
            {
                var r2 = (Result)Visit(context.expression(1));
                obj += $" = {r2.text} {Terminate} {Wrap}";
            }
            return obj;
        }

        public override object VisitNspackageControlSubStatement([NotNull] XyParser.NspackageControlSubStatementContext context)
        {
            var obj = "";
            var id = "";
            id = GetControlSub(context.id().GetText());
            if (context.functionSupportStatement().Length>0)
            {
                obj += id + BlockLeft;
                foreach (var item in context.functionSupportStatement())
                {
                    obj += Visit(item);
                }
                obj += BlockRight + Wrap;
            }
            else
            {
                obj += id + ";";
            }

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
