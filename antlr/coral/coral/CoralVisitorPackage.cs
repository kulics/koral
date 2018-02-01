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
            foreach(var item in context.packageSupportStatement())
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

        public override object VisitPackageInvariableStatement([NotNull] CoralParser.PackageInvariableStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = r1.permission + " " + r2.data + " " + r1.text + " = " + r2.text + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitFunctionMainStatement([NotNull] CoralParser.FunctionMainStatementContext context)
        {
            var obj = "void init(string[] args)" + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.functionSupportStatement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }
    }
}
