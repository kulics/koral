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
        public override object VisitExportStatement([NotNull] CoralParser.ExportStatementContext context)
        {
            var obj = "namespace " + Visit(context.nameSpace()) + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.exportSupportStatement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitImportStatement([NotNull] CoralParser.ImportStatementContext context)
        {
            var obj = "";

            foreach(var item in context.nameSpaceStatement())
            {
                obj += "using " + Visit(item) + Wrap;
            }
            return obj;
        }

        public override object VisitNameSpaceStatement([NotNull] CoralParser.NameSpaceStatementContext context)
        {
            var obj = Visit(context.nameSpace()) + context.Terminate().GetText();
            return obj;
        }

        public override object VisitNameSpace([NotNull] CoralParser.NameSpaceContext context)
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

        public override object VisitFunctionMainStatement([NotNull] CoralParser.FunctionMainStatementContext context)
        {
            var obj = "static class @ProgramMain" + Wrap + context.BlockLeft().GetText() + Wrap;

            obj += "static void Main(string[] args)" + Wrap + context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.functionSupportStatement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + Wrap;

            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }
    }
}
