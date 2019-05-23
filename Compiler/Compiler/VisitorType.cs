using Antlr4.Runtime.Misc;
using static Compiler.XsParser;

namespace Compiler {
    internal partial class Visitor {
        public override object VisitType([NotNull] TypeContext context) {
            var obj = "";
            obj = (string)Visit(context.GetChild(0));
            return obj;
        }

        public override object VisitTypeNullable([NotNull] TypeNullableContext context) {
            var obj = "";
            obj = Visit(context.typeNotNull()) as string;
            if (context.typeNotNull().GetChild(0) is TypeBasicContext &&
                context.typeNotNull().GetChild(0).GetText() != "{}" &&
                context.typeNotNull().GetChild(0).GetText() != "Str")
            {
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
        public override object VisitTypeArray([NotNull] TypeArrayContext context) {
            var obj = "";
            obj += $" { Visit(context.type())}[] ";
            return obj;
        }

        public override object VisitTypeList([NotNull] TypeListContext context) {
            var obj = "";
            obj += $" {Lst}<{ Visit(context.type())}> ";
            return obj;
        }

        public override object VisitTypeSet([NotNull] TypeSetContext context) {
            var obj = "";
            obj += $" {Set}<{ Visit(context.type())}> ";
            return obj;
        }

        public override object VisitTypeDictionary([NotNull] TypeDictionaryContext context) {
            var obj = "";
            obj += $" {Dic}<{ Visit(context.type(0))},{Visit(context.type(1))}> ";
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

        public override object VisitTypeAny([NotNull] TypeAnyContext context) {
            return Any;
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
                    obj = I8;
                    break;
                case TypeU8:
                    obj = U8;
                    break;
                case TypeI16:
                    obj = I16;
                    break;
                case TypeU16:
                    obj = U16;
                    break;
                case TypeI32:
                    obj = I32;
                    break;
                case TypeU32:
                    obj = U32;
                    break;
                case TypeI64:
                    obj = I64;
                    break;
                case TypeU64:
                    obj = U64;
                    break;
                case TypeF32:
                    obj = F32;
                    break;
                case TypeF64:
                    obj = F64;
                    break;
                case TypeChr:
                    obj = Chr;
                    break;
                case TypeStr:
                    obj = Str;
                    break;
                case TypeBool:
                    obj = Bool;
                    break;
                case TypeInt:
                    obj = Int;
                    break;
                case TypeNum:
                    obj = Num;
                    break;
                default:
                    obj = Any;
                    break;
            }
            return obj;
        }
    }
}
