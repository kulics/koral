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
            var obj = "namespace " + Visit(context.nameSpace()) + Wrap + context.BlockLeft().GetText() + Wrap;
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
            obj += "using " + Visit(context.nameSpace()) + context.Terminate().GetText();
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
            var obj = "static class XyProgramMain" + Wrap + context.BlockLeft().GetText() + Wrap;

            obj += "static void Main(string[] args)" + Wrap + context.BlockLeft().GetText() + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += context.BlockRight().GetText() + Wrap;

            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }
    }
}
