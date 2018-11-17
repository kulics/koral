using Antlr4.Runtime;
using Antlr4.Runtime.Misc;
using System;
using System.Collections.Generic;
using System.Text;
using static Compiler.XsParser;

namespace Compiler
{
    internal class ErrorListener : BaseErrorListener
    {
        string FileDir { get; set; }

        public ErrorListener(string FileDir)
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

    internal partial class Visitor : XsBaseVisitor<object>
    {
        public string FileName { get; set; }

        private const string Terminate = ";";
        private const string Wrap = "\r\n";

        private const string Any = "object";

        private const string i8 = "System.SByte";
        private const string i16 = "System.Int16";
        private const string i32 = "System.Int32";
        private const string i64 = "System.Int64";

        private const string u8 = "System.Byte";
        private const string u16 = "System.UInt16";
        private const string u32 = "System.UInt32";
        private const string u64 = "System.UInt64";

        private const string f32 = "System.Single";
        private const string f64 = "System.Double";
        
        private const string bl = "System.Boolean";
        private const string t = "true";
        private const string f = "false";

        private const string chr = "System.Char";
        private const string str = "System.String";
        private const string lst = "lst";
        private const string dic = "dic";

        private const string BlockLeft = "{";
        private const string BlockRight = "}";

        private const string Task = "System.Threading.Tasks.Task";

        public override object VisitProgram([NotNull] ProgramContext context)
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

        public override object VisitId([NotNull] IdContext context)
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
            else if (context.op.Type == IDPublic)
            {
                r.permission = "public";
                r.text += context.op.Text;
            }
            else if (context.op.Type == IDPrivate)
            {
                r.permission = "private";
                r.text += context.op.Text;
            }

            if (keywords.Exists(t => t == r.text))
            {
                r.text = "@" + r.text;
            }
            return r;
        }

        public override object VisitBool([NotNull] BoolContext context)
        {
            var r = new Result();
            if (context.t.Type == True)
            {
                r.data = bl;
                r.text = t;
            }
            else if (context.t.Type == False)
            {
                r.data = bl;
                r.text = f;
            }
            return r;
        }

        public override object VisitCallAs([NotNull] CallAsContext context)
        {
            var r = new Result();
            var type = (string)Visit(context.type());
            r.data = type;
            r.text = " as " + type + ")";
            return r;
        }

        public override object VisitCallIs([NotNull] CallIsContext context)
        {
            var r = new Result();
            var type = (string)Visit(context.type());
            r.data = bl;
            r.text = " is " + type + ")";
            return r;
        }

        public override object VisitAnnotation([NotNull] AnnotationContext context)
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

        public override object VisitAnnotationList([NotNull] AnnotationListContext context)
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

        public override object VisitAnnotationItem([NotNull] AnnotationItemContext context)
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

        public override object VisitAnnotationAssign([NotNull] AnnotationAssignContext context)
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
