using Antlr4.Runtime;
using Antlr4.Runtime.Misc;
using System;

namespace XyLang.Compile
{
    internal class XyLangErrorListener : BaseErrorListener
    {
        string FileDir { get; set; }

        public XyLangErrorListener(string FileDir)
        {
            this.FileDir = FileDir;
        }

        public override void SyntaxError([NotNull] IRecognizer recognizer, [Nullable] IToken offendingSymbol, int line, int charPositionInLine, [NotNull] string msg, [Nullable] RecognitionException e)
        {
            base.SyntaxError(recognizer, offendingSymbol, line, charPositionInLine, msg, e);
            Console.WriteLine("------Syntax Error------");
            Console.WriteLine($"File: {FileDir}");
            Console.WriteLine($"Line: {line}  Column: {charPositionInLine}");
            Console.WriteLine($"OffendingSymbol: {offendingSymbol.Text}");
            Console.WriteLine($"Message: {msg}");
        }
    }

    internal partial class XyLangVisitor : XyBaseVisitor<object>
    {
        public string FileName { get; set; }

        private const string Terminate = ";";
        private const string Wrap = "\r\n";

        private const string Any = "object";

        private const string I8 = "i8";
        private const string I16 = "i16";
        private const string I32 = "i32";
        private const string I64 = "i64";

        private const string U8 = "u8";
        private const string U16 = "u16";
        private const string U32 = "u32";
        private const string U64 = "u64";

        private const string F32 = "f32";
        private const string F64 = "f64";

        private const string Bool = "bl";
        private const string True = "true";
        private const string False = "false";

        private const string Chr = "chr";
        private const string Str = "str";
        private const string List = "lst";
        private const string Dictionary = "dic";

        private const string BlockLeft = "{";
        private const string BlockRight = "}";

        private const string Task = "System.Threading.Tasks.Task";

        public override object VisitProgram([NotNull] XyParser.ProgramContext context)
        {
            var list = context.statement();
            var result = "";
            foreach (var item in list)
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
            var r = new Result
            {
                data = "var"
            };
            if (context.typeBasic() != null)
            {
                r.permission = "public";
                r.text += context.typeBasic().GetText();
            }
            else if (context.linqKeyword() != null)
            {
                r.permission = "public";
                r.text += Visit(context.linqKeyword());
            }
            else if (context.op.Type == XyParser.IDPublic)
            {
                r.permission = "public";
                r.text += context.op.Text;
            }
            else if (context.op.Type == XyParser.IDPrivate)
            {
                r.permission = "private";
                r.text += context.op.Text;
            }

            if (keywords.Exists(t => t == r.text))
            {
                r.text = "@" + r.text;
            }

            var b = r.text;
            return r;
        }

        public override object VisitBool([NotNull] XyParser.BoolContext context)
        {
            var r = new Result();
            if (context.t.Type == XyParser.True)
            {
                r.data = Bool;
                r.text = True;
            }
            else if (context.t.Type == XyParser.False)
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
            if (context.id() != null)
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
            for (int i = 0; i < context.annotationItem().Length; i++)
            {
                if (i > 0)
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
            for (int i = 0; i < context.annotationAssign().Length; i++)
            {
                if (i > 0)
                {
                    obj += "," + Visit(context.annotationAssign(i));
                }
                else
                {
                    obj += "(" + Visit(context.annotationAssign(i));
                }
            }
            if (context.annotationAssign().Length > 0)
            {
                obj += ")";
            }
            return obj;
        }

        public override object VisitAnnotationAssign([NotNull] XyParser.AnnotationAssignContext context)
        {
            var obj = "";
            var id = "";
            if (context.id() != null)
            {
                id = ((Result)Visit(context.id())).text + "=";
            }
            var r = (Result)Visit(context.expression());
            obj = id + r.text;
            return obj;
        }
    }
}
