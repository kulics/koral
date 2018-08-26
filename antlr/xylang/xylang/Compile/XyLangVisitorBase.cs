using Antlr4.Runtime.Misc;

namespace XyLang.Compile
{
    internal partial class XyLangVisitor : XyBaseVisitor<object>
    {
        public string FileName { get; set; }

        private const string Terminate = ";";
        private const string Wrap = "\r\n";

        private const string Any = "object";

        private const string I8 = "I8";
        private const string I16 = "I16";
        private const string I32 = "I32";
        private const string I64 = "I64";

        private const string U8 = "U8";
        private const string U16 = "U16";
        private const string U32 = "U32";
        private const string U64 = "U64";

        private const string F32 = "F32";
        private const string F64 = "F64";

        private const string Bool = "bool";
        private const string True = "true";
        private const string False = "false";

        private const string Str = "Str";
        private const string List = "Lst";
        private const string Dictionary = "Dic";

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
            else if (context.sharpId() != null)
            {
                r.permission = "public";
                r.text += Visit(context.sharpId());
            }
            else if (context.op.Type == XyParser.IDPublic)
            {
                r.permission = "public";
                r.text += context.op.Text;
                if (keywords.IndexOf(r.text) >= 0)
                {
                    r.text = "@" + r.text;
                }
            }
            else if (context.op.Type == XyParser.IDPrivate)
            {
                r.permission = "private";
                r.text += context.op.Text;
            }

            return r;
        }

        public override object VisitSharpId([NotNull] XyParser.SharpIdContext context)
        {
            var sharptype = context.typeBasic().GetText();
            switch (sharptype)
            {
                case I8:
                    sharptype = "sbyte";
                    break;
                case I16:
                    sharptype = "short";
                    break;
                case I32:
                    sharptype = "int";
                    break;
                case I64:
                    sharptype = "long";
                    break;

                case U8:
                    sharptype = "byte";
                    break;
                case U16:
                    sharptype = "ushort";
                    break;
                case U32:
                    sharptype = "uint";
                    break;
                case U64:
                    sharptype = "ulong";
                    break;

                case F32:
                    sharptype = "float";
                    break;
                case F64:
                    sharptype = "double";
                    break;

                case Bool:
                    sharptype = "bool";
                    break;

                case Str:
                    sharptype = "string";
                    break;

                default:
                    break;
            }
            return sharptype;
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
