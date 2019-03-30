using System.Collections.Generic;
using Antlr4.Runtime.Misc;
using static Compiler.XsParser;

namespace Compiler
{
    internal partial class Visitor
    {
        public override object VisitStatement([NotNull] StatementContext context) {
            var obj = "";
            var ns = (Namespace)Visit(context.exportStatement());
            // import library
            obj += $"using Library;{Wrap}using static Library.Lib;{Wrap}";
            obj += ns.imports + Wrap;
            if (context.annotationSupport() != null) {
                obj += Visit(context.annotationSupport());
            }
            obj += $"namespace {ns.name + Wrap + BlockLeft + Wrap}";

            var content = "";
            foreach (var item in context.namespaceSupportStatement()) {
                content += Visit(item);
            }
            obj += content;
            obj += BlockRight + Wrap;
            return obj;
        }

        private class Namespace
        {
            public string name;
            public string imports;
        }

        public override object VisitExportStatement([NotNull] ExportStatementContext context) {
            var obj = new Namespace {
                name = (string)Visit(context.nameSpace())
            };
            foreach (var item in context.importStatement()) {
                obj.imports += (string)Visit(item);
            }
            return obj;
        }

        public override object VisitImportStatement([NotNull] ImportStatementContext context) {
            var obj = "";
            if (context.annotationSupport() != null) {
                obj += Visit(context.annotationSupport());
            }
            if (context.id() != null) {
                var ns = (string)Visit(context.nameSpace());
                obj += "using static " + ns;
                if (context.id() != null) {
                    var r = (Result)Visit(context.id());

                    obj += "." + r.text;
                }

                obj += Terminate;
            } else {
                obj += "using " + Visit(context.nameSpace()) + Terminate;
            }
            obj += Wrap;
            return obj;
        }

        public override object VisitNameSpace([NotNull] NameSpaceContext context) {
            var obj = "";
            for (int i = 0; i < context.id().Length; i++) {
                var id = (Result)Visit(context.id(i));
                if (i == 0) {
                    obj += "" + id.text;
                } else {
                    obj += "." + id.text;
                }
            }
            return obj;
        }

        public override object VisitNameSpaceItem([NotNull] NameSpaceItemContext context) {
            var obj = "";
            for (int i = 0; i < context.id().Length; i++) {
                var id = (Result)Visit(context.id(i));
                if (i == 0) {
                    obj += "" + id.text;
                } else {
                    obj += "." + id.text;
                }
            }
            return obj;
        }

        public override object VisitName([NotNull] NameContext context) {
            var obj = "";
            for (int i = 0; i < context.id().Length; i++) {
                var id = (Result)Visit(context.id(i));
                if (i == 0) {
                    obj += "" + id.text;
                } else {
                    obj += "." + id.text;
                }
            }
            return obj;
        }

        public override object VisitEnumStatement([NotNull] EnumStatementContext context) {
            var obj = "";
            var id = (Result)Visit(context.id());
            var header = "";
            if (context.annotationSupport() != null) {
                header += Visit(context.annotationSupport());
            }
            header += id.permission + " enum " + id.text;
            header += Wrap + BlockLeft + Wrap;
            for (int i = 0; i < context.enumSupportStatement().Length; i++) {
                obj += Visit(context.enumSupportStatement(i));
            }
            obj += BlockRight + Terminate + Wrap;
            obj = header + obj;
            return obj;
        }

        public override object VisitEnumSupportStatement([NotNull] EnumSupportStatementContext context) {
            var id = (Result)Visit(context.id());
            if (context.Integer() != null) {
                var op = "";
                if (context.add() != null) {
                    op = (string)Visit(context.add());
                }
                id.text += " = " + op + context.Integer().GetText();
            }
            return id.text + ",";
        }

        public override object VisitPackageStaticStatement([NotNull] PackageStaticStatementContext context) {
            var id = (Result)Visit(context.id());
            var obj = "";
            var Init = "";
            // 获取构造数据
            Init += "static " + id.text + "()" + BlockLeft + Wrap;
            // 处理构造函数
            if (context.packageInitStatement() != null) {
                Init += Visit(context.packageInitStatement());
            }
            Init += BlockRight;
            obj = Init + obj;
            foreach (var item in context.packageStaticSupportStatement()) {
                obj += Visit(item);
            }
            obj += BlockRight + Terminate + Wrap;
            var header = "";
            if (context.annotationSupport() != null) {
                header += Visit(context.annotationSupport());
            }
            header += $"{id.permission} partial class {id.text}";
            // 泛型
            var templateContract = "";
            if (context.templateDefine() != null) {
                var template = (TemplateItem)Visit(context.templateDefine());
                header += template.Template;
                templateContract = template.Contract;
            }
            header += templateContract + Wrap + BlockLeft + Wrap;
            obj = header + obj;
            return obj;
        }

        public override object VisitNamespaceFunctionStatement([NotNull] NamespaceFunctionStatementContext context) {
            var id = (Result)Visit(context.id());
            var obj = "";
            if (context.annotationSupport() != null) {
                obj += Visit(context.annotationSupport());
            }
            // 异步
            if (context.t.Type == FlowRight) {
                var pout = (string)Visit(context.parameterClauseOut());
                if (pout != "void") {
                    pout = $"{Task}<{pout}>";
                } else {
                    pout = Task;
                }
                obj += $"{id.permission} async static {pout} {id.text}";
            } else {
                obj += $"{id.permission} static {Visit(context.parameterClauseOut())} {id.text}";
            }

            // 泛型
            var templateContract = "";
            if (context.templateDefine() != null) {
                var template = (TemplateItem)Visit(context.templateDefine());
                obj += template.Template;
                templateContract = template.Contract;
            }
            obj += Visit(context.parameterClauseIn()) + templateContract + Wrap + BlockLeft + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += BlockRight + Wrap;
            return obj;
        }

        public override object VisitNamespaceConstantStatement([NotNull] NamespaceConstantStatementContext context) {
            var id = (Result)Visit(context.id());
            var expr = (Result)Visit(context.expression());
            var typ = "";
            if (context.type() != null) {
                typ = (string)Visit(context.type());
            } else {
                typ = (string)expr.data;
            }

            var obj = "";
            if (context.annotationSupport() != null) {
                obj += Visit(context.annotationSupport());
            }
            switch (typ) {
                case i8:
                    typ = "ubyte";
                    break;
                case i16:
                    typ = "short";
                    break;
                case i32:
                    typ = "int";
                    break;
                case i64:
                    typ = "long";
                    break;

                case u8:
                    typ = "byte";
                    break;
                case u16:
                    typ = "ushort";
                    break;
                case u32:
                    typ = "uint";
                    break;
                case u64:
                    typ = "ulong";
                    break;

                case f32:
                    typ = "float";
                    break;
                case f64:
                    typ = "double";
                    break;

                case str:
                    typ = "string";
                    break;
                default:
                    break;
            }
            obj += $"{id.permission} const {typ} {id.text} = {expr.text} {Terminate} {Wrap}";
            return obj;
        }

        public override object VisitNamespaceVariableStatement([NotNull] NamespaceVariableStatementContext context) {
            var r1 = (Result)Visit(context.id());
            var isMutable = r1.isVirtual;
            var typ = "";
            Result r2 = null;
            if (context.expression() != null) {
                r2 = (Result)Visit(context.expression());
                typ = (string)r2.data;
            }
            if (context.type() != null) {
                typ = (string)Visit(context.type());
            }
            var obj = "";
            if (context.annotationSupport() != null) {
                obj += Visit(context.annotationSupport());
            }

            obj += $"{r1.permission} static {typ} {r1.text}";
            if (r2 != null) {
                obj += $" = {r2.text} {Terminate} {Wrap}";
            } else {
                obj += Terminate + Wrap;
            }
            return obj;
        }

        public override object VisitNamespaceControlStatement([NotNull] NamespaceControlStatementContext context) {
            var r1 = (Result)Visit(context.id());
            var isMutable = r1.isVirtual;
            var typ = "";
            Result r2 = null;
            if (context.expression() != null) {
                r2 = (Result)Visit(context.expression());
                typ = (string)r2.data;
            }
            if (context.type() != null) {
                typ = (string)Visit(context.type());
            }
            var obj = "";
            if (context.annotationSupport() != null) {
                obj += Visit(context.annotationSupport());
            }
            if (context.packageControlSubStatement().Length > 0) {
                obj += $"{r1.permission} static {typ} {r1.text + BlockLeft}";
                var record = new Dictionary<string, bool>();
                foreach (var item in context.packageControlSubStatement()) {
                    var temp = (Visit(item) as Result);
                    obj += temp.text;
                    record[temp.data as string] = true;
                }
                if (r2 != null) {
                    obj = $"protected static {typ} _{r1.text} = {r2.text}; {Wrap}" + obj;
                    if (!record.ContainsKey("get")) {
                        obj += $"get {{ return _{r1.text}; }}";
                    }
                    if (isMutable && !record.ContainsKey("set")) {
                        obj += $"set {{ _{r1.text} = value; }}";
                    }
                }
                obj += BlockRight + Wrap;
            } else {
                if (isMutable) {
                    obj += $"{r1.permission} static {typ} {r1.text} {{ get;set; }}";
                    if (r2 != null) {
                        obj += $" = {r2.text} {Terminate} {Wrap}";
                    } else {
                        obj += Wrap;
                    }
                } else {
                    obj += $"{r1.permission} static {typ} {r1.text} {{ get; }}";
                    if (r2 != null) {
                        obj += $" = {r2.text} {Terminate} {Wrap}";
                    } else {
                        obj += Wrap;
                    }
                }
            }
            return obj;
        }

        public (string, string) GetControlSub(string id) {
            var typ = "";
            switch (id) {
                case "get":
                    id = " get ";
                    typ = "get";
                    break;
                case "set":
                    id = " set ";
                    typ = "set";
                    break;
                case "_get":
                    id = " protected get ";
                    typ = "get";
                    break;
                case "_set":
                    id = " protected set ";
                    typ = "set";
                    break;
                case "add":
                    id = " add ";
                    typ = "add";
                    break;
                case "remove":
                    id = " remove ";
                    typ = "remove";
                    break;
                default:
                    break;
            }
            return (id, typ);
        }
    }
}
