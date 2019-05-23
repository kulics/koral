using Antlr4.Runtime;
using Antlr4.Runtime.Misc;
using System;
using Library;
using static Compiler.XsParser;

namespace Compiler {
    internal class ErrorListener : BaseErrorListener {
        private string FileDir { get; set; }

        public ErrorListener(string FileDir) {
            this.FileDir = FileDir;
        }

        public override void SyntaxError([NotNull] IRecognizer recognizer, [Nullable] IToken offendingSymbol, int line, int charPositionInLine, [NotNull] string msg, [Nullable] RecognitionException e) {
            base.SyntaxError(recognizer, offendingSymbol, line, charPositionInLine, msg, e);
            Console.WriteLine("------Syntax Error------");
            Console.WriteLine($"File: {FileDir}");
            Console.WriteLine($"Line: {line}  Column: {charPositionInLine}");
            Console.WriteLine($"OffendingSymbol: {offendingSymbol.Text}");
            Console.WriteLine($"Message: {msg}");
        }
    }

    internal partial class Visitor : XsBaseVisitor<object> {
        public string FileName { get; set; }

        private const string Terminate = ";";
        private const string Wrap = "\r\n";

        private const string Any = "object";
        private const string Int = "int";
        private const string Num = "double";
        private const string I8 = "sbyte";
        private const string I16 = "short";
        private const string I32 = "int";
        private const string I64 = "long";

        private const string U8 = "byte";
        private const string U16 = "ushort";
        private const string U32 = "uint";
        private const string U64 = "ulong";

        private const string F32 = "float";
        private const string F64 = "double";

        private const string Bool = "bool";
        private const string T = "true";
        private const string F = "false";

        private const string Chr = "char";
        private const string Str = "string";
        private const string Lst = "Lst";
        private const string Set = "Set";
        private const string Dic = "Dic";

        private const string BlockLeft = "{";
        private const string BlockRight = "}";

        private const string Task = "System.Threading.Tasks.Task";

        public override object VisitProgram([NotNull] ProgramContext context) {
            var list = context.statement();
            var result = "";
            foreach (var item in list) {
                result += VisitStatement(item);
            }
            return result;
        }

        public class Result {
            public object data { get; set; }
            public string text { get; set; }
            public string permission { get; set; }
            public bool isVirtual { get; set; }
        }

        public override object VisitId([NotNull] IdContext context) {
            var r = new Result {
                data = "var"
            };
            var first = (Result)Visit(context.GetChild(0));
            r.permission = first.permission;
            r.text = first.text;
            r.isVirtual = first.isVirtual;
            if (context.ChildCount >= 2) {
                for (int i = 1; i < context.ChildCount; i++) {
                    var other = (Result)Visit(context.GetChild(i));
                    r.text += "_" + other.text;
                }
            }

            if (keywords.Exists(t => t == r.text)) {
                r.text = "@" + r.text;
            }
            return r;
        }

        public override object VisitIdItem([NotNull] IdItemContext context) {
            var r = new Result{
                data = "var"
            };
            if (context.typeBasic() != null) {
                r.permission = "public";
                r.text += context.typeBasic().GetText();
            } else if (context.linqKeyword() != null) {
                r.permission = "public";
                r.text += Visit(context.linqKeyword());
            } else if (context.op.Type == IDPublic) {
                r.permission = "public";
                r.text += context.op.Text;
                r.isVirtual = r.text[0].is_Upper();
            } else if (context.op.Type == IDPrivate) {
                r.permission = "protected";
                r.text += context.op.Text;
                r.isVirtual = r.text[r.text.find_first(it => it != '_')].is_Upper();
            }
            return r;
        }

        public override object VisitBool([NotNull] BoolContext context) {
            var r = new Result();
            if (context.t.Type == True) {
                r.data = Bool;
                r.text = T;
            } else if (context.t.Type == False) {
                r.data = Bool;
                r.text = F;
            }
            return r;
        }

        public override object VisitAnnotationSupport([NotNull] AnnotationSupportContext context) {
            return (string)Visit(context.annotation());
        }

        public override object VisitAnnotation([NotNull] AnnotationContext context) {
            var obj = "";
            var id = "";
            if (context.id() != null) {
                id = ((Result)Visit(context.id())).text + ":";
            }

            var r = (string)Visit(context.annotationList());
            obj += "[" + id + r + "]";
            return obj;
        }

        public override object VisitAnnotationList([NotNull] AnnotationListContext context) {
            var obj = "";
            for (int i = 0; i < context.annotationItem().Length; i++) {
                if (i > 0) {
                    obj += "," + Visit(context.annotationItem(i));
                } else {
                    obj += Visit(context.annotationItem(i));
                }
            }
            return obj;
        }

        public override object VisitAnnotationItem([NotNull] AnnotationItemContext context) {
            var obj = "";
            obj += ((Result)Visit(context.id())).text;
            for (int i = 0; i < context.annotationAssign().Length; i++) {
                if (i > 0) {
                    obj += "," + Visit(context.annotationAssign(i));
                } else {
                    obj += "(" + Visit(context.annotationAssign(i));
                }
            }
            if (context.annotationAssign().Length > 0) {
                obj += ")";
            }
            return obj;
        }

        public override object VisitAnnotationAssign([NotNull] AnnotationAssignContext context) {
            var obj = "";
            var id = "";
            if (context.id() != null) {
                id = ((Result)Visit(context.id())).text + "=";
            }
            var r = (Result)Visit(context.expression());
            obj = id + r.text;
            return obj;
        }
    }
}
