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
            obj += id.permission + " interface " + id.text + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.protocolSupportStatement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitProtocolInvariableStatement([NotNull] CoralParser.ProtocolInvariableStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = "";
            if(r1.permission == "public")
            {
                obj += r2.data + " " + r1.text + " {get;set;} " + Wrap;
            }
            //r1.permission + " " + r2.data + " " + r1.text + " = " + r2.text + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitProtocolFunctionStatement([NotNull] CoralParser.ProtocolFunctionStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = "";
            if(id.permission == "public")
            {
                obj += Visit(context.parameterClauseOut()) + id.text
                + Visit(context.parameterClauseIn()) + context.Terminate().GetText() + Wrap;
            }
            //var obj = id.permission + Visit(context.parameterClauseOut()) + id.text
            //    + Visit(context.parameterClauseIn()) + Wrap + context.BlockLeft().GetText() + Wrap;
            //foreach(var item in context.functionSupportStatement())
            //{
            //    obj += Visit(item);
            //}
            //obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }
    }
}
