using Antlr4.Runtime.Misc;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace XyLang.Compile
{
    partial class XyLangVisitor : XyBaseVisitor<object>
    {
        public string FileName { get; set; }

        const string Terminate = ";";
        const string Wrap = "\r\n";
        const string Any = "object";
        const string I32 = "int";
        const string F64 = "double";
        const string Bool = "bool";
        const string Str = "string";
        const string BlockLeft = "{";
        const string BlockRight = "}";
        const string True = "true";
        const string False = "false";

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
            public string callType { get; set; }
            public int bracketTime { get; set; }
            public bool isCall { get; set; }
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
                r.data = Bool;
                r.text = True;
            }
            else if(context.t.Type == XyParser.False)
            {
                r.data = Bool;
                r.text = False;
            }
            return r;
        }

        public override object VisitCallAs([NotNull] XyParser.CallAsContext context)
        {
            var r = new Result();
            var type = (string)Visit(context.type());
            r.data = type;
            r.text = " as " + type + ")";
            return r;
        }

        public override object VisitCallIs([NotNull] XyParser.CallIsContext context)
        {
            var r = new Result();
            var type = (string)Visit(context.type());
            r.data = Bool;
            r.text = " is " + type + ")";
            return r;
        }

        public override object VisitAnnotation([NotNull] XyParser.AnnotationContext context)
        {
            var obj = "";
            var id = "";
            if(context.id() != null)
            {
                id = ((Result)Visit(context.id())).text + ":";
            }

            var r = (string)Visit(context.annotationList());
            obj += "[" + id + r + "]";
            return obj;
        }

        public override object VisitAnnotationList([NotNull] XyParser.AnnotationListContext context)
        {
            var obj = "";
            for(int i = 0; i < context.annotationItem().Length; i++)
            {
                if(i > 0)
                {
                    obj += "," + Visit(context.annotationItem(i));
                }
                else
                {
                    obj += Visit(context.annotationItem(i));
                }
            }
            return obj;
        }

        public override object VisitAnnotationItem([NotNull] XyParser.AnnotationItemContext context)
        {
            var obj = "";
            obj += ((Result)Visit(context.id())).text;
            for(int i = 0; i < context.annotationAssign().Length; i++)
            {
                if(i > 0)
                {
                    obj += "," + Visit(context.annotationAssign(i));
                }
                else
                {
                    obj += "(" + Visit(context.annotationAssign(i));
                }
            }
            if(context.annotationAssign().Length > 0)
            {
                obj += ")";
            }
            return obj;
        }

        public override object VisitAnnotationAssign([NotNull] XyParser.AnnotationAssignContext context)
        {
            var obj = "";
            var id = "";
            if(context.id() != null)
            {
                id = ((Result)Visit(context.id())).text + "=";
            }
            var r = (Result)Visit(context.expression());
            obj = id + r.text;
            return obj;
        }
    }
}
