using Antlr4.Runtime.Misc;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace xylang
{
    partial class XyLangVisitor : XyBaseVisitor<object>
    {
        const string Wrap = "\r\n";

        public override object VisitProgram([NotNull] XyParser.ProgramContext context)
        {
            var list = context.statement();
            var result = "";
            foreach(var item in list)
            {
                result += VisitStatement(item);
            }
            return result;
        }

        public class Result
        {
            public object data { get; set; }
            public string text { get; set; }
            public string permission { get; set; }
            public bool isIndex { get; set; }
        }

        public override object VisitId([NotNull] XyParser.IdContext context)
        {
            var r = new Result();
            r.data = "var";
            if(context.typeBasic() != null)
            {
                r.permission = "public";
                r.text += context.typeBasic().GetText();
            }
            else if(context.linqKeyword() != null)
            {
                r.permission = "public";
                r.text += Visit(context.linqKeyword());
            }
            else if(context.op.Type == XyParser.IDPublic)
            {
                r.permission = "public";
                r.text += context.op.Text;
            }
            else if(context.op.Type == XyParser.IDPrivate)
            {
                r.permission = "private";
                r.text += context.op.Text;
            }

            if(keywords.IndexOf(r.text) >= 0)
            {
                r.text = "@" + r.text;
            }
            return r;
        }

        public override object VisitBool([NotNull] XyParser.BoolContext context)
        {
            var r = new Result();
            if(context.t.Type == XyParser.True)
            {
                r.data = "bool";
                r.text = context.True().GetText();
            }
            else if(context.t.Type == XyParser.False)
            {
                r.data = "bool";
                r.text = context.False().GetText();
            }
            return r;
        }

        public override object VisitCallAs([NotNull] XyParser.CallAsContext context)
        {
            var r = new Result();
            var type = (string)Visit(context.type());
            r.data = type;
            r.text = type;
            return r;
        }

        public override object VisitCallIs([NotNull] XyParser.CallIsContext context)
        {
            var r = new Result();
            var type = (string)Visit(context.type());
            r.data = "bool";
            r.text = type;
            return r;
        }

        public override object VisitAnnotation([NotNull] XyParser.AnnotationContext context)
        {
            var obj = "";
            var r = (Result)Visit(context.expressionList());
            obj += "[" + r.text + "]";
            return obj;
        }
    }
}
