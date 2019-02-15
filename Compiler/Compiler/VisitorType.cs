using Antlr4.Runtime.Misc;
using static Compiler.XsParser;

namespace Compiler {
    internal partial class Visitor {
        public override object VisitTypeNullable([NotNull] TypeNullableContext context) {
            var obj = "";
            obj = Visit(context.typeNotNull()) as string;
            if (context.typeNotNull().GetChild(0) is TypeBasicContext &&
                context.typeNotNull().GetChild(0).GetText() != "obj" &&
                 context.typeNotNull().GetChild(0).GetText() != "str") {
                obj += "?";
            }
            return obj;
        }

        public override object VisitTypeTuple([NotNull] TypeTupleContext context) {
            var obj = "";
            obj += "(";
            for (int i = 0; i < context.type().Length; i++) {
                if (i == 0) {
                    obj += Visit(context.type(i));
                } else {
                    obj += "," + Visit(context.type(i));
                }
            }
            obj += ")";
            return obj;
        }

        public override object VisitGetType([NotNull] GetTypeContext context) {
            var r = new Result {
                data = "System.Type"
            };
            if (context.type() is null) {
                r.text = $"{((Result)Visit(context.expression())).text} .GetType()";
            } else {
                r.text = $"typeof( { Visit(context.type())} )";
            }
            return r;
        }

        public override object VisitTypeList([NotNull] TypeListContext context) {
            var obj = "";
            obj += $" {lst}<{ Visit(context.type())}> ";
            return obj;
        }

        public override object VisitTypeArray([NotNull] TypeArrayContext context) {
            var obj = "";
            obj += Visit(context.type()) + "[]";
            return obj;
        }

        public override object VisitTypeDictionary([NotNull] TypeDictionaryContext context) {
            var obj = "";
            obj += $" {dic}<{ Visit(context.type(0))},{Visit(context.type(1))}> ";
            return obj;
        }

        public override object VisitTypePackage([NotNull] TypePackageContext context) {
            var obj = "";
            obj += Visit(context.nameSpaceItem());
            if (context.templateCall() != null) {
                obj += Visit(context.templateCall());
            }
            return obj;
        }

        public override object VisitTypeFunction([NotNull] TypeFunctionContext context) {
            var obj = "";
            var @in = (string)Visit(context.typeFunctionParameterClause(0));
            var @out = (string)Visit(context.typeFunctionParameterClause(1));
            if (@out.Length == 0) {
                if (@in.Length == 0) {
                    obj += "Action";
                } else {
                    obj += "Action<";
                    obj += @in;
                    obj += ">";
                }
            } else {
                if (@out.IndexOf(",") >= 0) {
                    @out = "(" + @out + ")";
                }
                if (@in.Length == 0) {
                    obj += "Func<";
                    obj += @out;
                    obj += ">";
                } else {
                    obj += "Func<";
                    obj += @in + ", ";
                    obj += @out;
                    obj += ">";
                }
            }
            return obj;
        }

        public override object VisitTypeFunctionParameterClause([NotNull] TypeFunctionParameterClauseContext context) {
            var obj = "";
            for (int i = 0; i <= context.type().Length - 1; i++) {
                string p = (string)Visit(context.type(i));
                if (i == 0) {
                    obj += p;
                } else {
                    obj += $", {p}";
                }
            }
            return obj;
        }

        public override object VisitTypeBasic([NotNull] TypeBasicContext context) {
            var obj = "";
            switch (context.t.Type) {
                case TypeI8:
                    obj = i8;
                    break;
                case TypeU8:
                    obj = u8;
                    break;
                case TypeI16:
                    obj = i16;
                    break;
                case TypeU16:
                    obj = u16;
                    break;
                case TypeI32:
                    obj = i32;
                    break;
                case TypeU32:
                    obj = u32;
                    break;
                case TypeI64:
                    obj = i64;
                    break;
                case TypeU64:
                    obj = u64;
                    break;
                case TypeF32:
                    obj = f32;
                    break;
                case TypeF64:
                    obj = f64;
                    break;
                case TypeChr:
                    obj = chr;
                    break;
                case TypeStr:
                    obj = str;
                    break;
                case TypeBool:
                    obj = bl;
                    break;
                case TypeAny:
                    obj = Any;
                    break;
                default:
                    obj = Any;
                    break;
            }
            return obj;
        }
    }
}
