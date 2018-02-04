using Antlr4.Runtime.Misc;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace coral
{
    partial class CoralVisitorBase
    {
        public override object VisitPackageStatement([NotNull] CoralParser.PackageStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = id.permission + " class " + id.text + Wrap + context.BlockLeft().GetText() + Wrap;
            var hasInit = false;
            foreach(var item in context.packageSupportStatement())
            {
                // 处理构造函数
                if(item.GetChild(0).GetType() == typeof(CoralParser.PackageInitStatementContext))
                {
                    if(!hasInit && !context.parameterClauseIn().IsEmpty)
                    {
                        obj += "public " + id.text + Visit(context.parameterClauseIn());
                        obj += Visit(item);
                        hasInit = true;
                    }
                }
                else
                {
                    obj += Visit(item);
                }
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitPackageInvariableStatement([NotNull] CoralParser.PackageInvariableStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = r1.permission + " " + r2.data + " " + r1.text + " = " + r2.text + context.Terminate().GetText() + Wrap;
            return obj;
        }


        public override object VisitPackageInitStatement([NotNull] CoralParser.PackageInitStatementContext context)
        {
            var obj = context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.functionSupportStatement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitProtocolStatement([NotNull] CoralParser.ProtocolStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = "";
            var staticProtocol = "";
            var interfaceProtocol = "";
            foreach(var item in context.protocolSupportStatement())
            {
                var r = (Result)Visit(item);
                if(r.permission == "public")
                {
                    interfaceProtocol += r.text;
                }
                else
                {
                    staticProtocol += r.text;
                }
            }
            obj += "public interface @Interface" + id.text.Substring(1) + Wrap + context.BlockLeft().GetText() + Wrap;
            obj += interfaceProtocol;
            obj += context.BlockRight().GetText() + Wrap;

            obj += "public static class " + id.text + Wrap + context.BlockLeft().GetText() + Wrap;
            obj += staticProtocol;
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitProtocolInvariableStatement([NotNull] CoralParser.ProtocolInvariableStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var r = new Result();
            if(r1.permission == "public")
            {
                r.permission = "public";
                r.text += r2.data + " " + r1.text + " {get;set;} " + Wrap;
            }
            else
            {
                r.permission = "private";
                r.text += "public const " + r2.data + " " + r1.text + " = " + r2.text + context.Terminate().GetText() + Wrap;
            }
            return r;
        }

        public override object VisitProtocolFunctionStatement([NotNull] CoralParser.ProtocolFunctionStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var r = new Result();
            if(id.permission == "public")
            {
                r.permission = "public";
                r.text += Visit(context.parameterClauseOut()) + id.text
                + Visit(context.parameterClauseIn()) + context.Terminate().GetText() + Wrap;
            }
            else
            {
                r.permission = "private";
                r.text += "public static " + Visit(context.parameterClauseOut()) + id.text
                + Visit(context.parameterClauseIn()) + Wrap + context.BlockLeft().GetText() + Wrap;
                foreach(var item in context.functionSupportStatement())
                {
                    r.text += Visit(item);
                }
                r.text += context.BlockRight().GetText() + Wrap;
            }
            return r;
        }
    }
}
