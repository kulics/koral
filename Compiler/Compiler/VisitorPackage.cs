using Antlr4.Runtime.Misc;
using System.Collections.Generic;
using static Compiler.XsParser;

namespace Compiler {
    internal partial class Visitor {
        public override object VisitExtend([NotNull] ExtendContext context) {
            var r = new Result {
                data = Visit(context.type())
            };
            r.text += "(";
            if (context.expressionList() != null) {
                r.text += (Visit(context.expressionList()) as Result).text;
            }
            r.text += ")";
            return r;
        }

        public override object VisitPackageExtensionStatement([NotNull] PackageExtensionStatementContext context) {
            var id = (Result)Visit(context.id());
            var obj = "";
            obj += $"{id.permission} partial class {id.text}";
            // 泛型
            if (context.templateDefine() != null) {
                obj += Visit(context.templateDefine());
            }
            obj += BlockLeft + Wrap;
            foreach (var item in context.packageExtensionSupportStatement()) {
                obj += Visit(item);
            }
            obj += BlockRight + Terminate + Wrap;
            return obj;
        }

        public override object VisitPackageStatement([NotNull] PackageStatementContext context) {
            var id = (Result)Visit(context.id());
            var obj = "";
            var Init = "";
            var extend = "";

            if (context.extend() != null) {
                extend = (string)((Result)Visit(context.extend())).data;
            }
            // 获取构造数据
            var paramConstructor = (string)Visit(context.parameterClausePackage());
            Init += "public " + id.text + paramConstructor;
            // 加载继承
            if (context.extend() != null) {
                Init += " :base " + ((Result)Visit(context.extend())).text;
            }
            Init += BlockLeft;
            foreach (var item in context.packageSupportStatement()) {
                obj += Visit(item);
            }
            if (context.packageOverrideStatement() != null) {
                obj += (string)Visit(context.packageOverrideStatement());
            }
            // 处理构造函数
            if (context.packageInitStatement() != null) {
                Init += Visit(context.packageInitStatement());
            }
            Init += BlockRight;
            obj = Init + obj;
            obj += BlockRight + Terminate + Wrap;
            var header = "";
            if (context.annotationSupport() != null) {
                header += Visit(context.annotationSupport());
            }
            header += $"{id.permission} partial class {id.text}";
            // 泛型
            if (context.templateDefine() != null) {
                header += Visit(context.templateDefine());
            }
            if (extend.Length > 0) {
                header += ":";
                if (extend.Length > 0) {
                    header += extend;
                }
            }

            header += Wrap + BlockLeft + Wrap;
            obj = header + obj;

            foreach (var item in context.protocolImplementStatement()) {
                obj += $"{id.permission} partial class {id.text} {(string)Visit(item)} {Wrap}";
            }

            return obj;
        }

        public override object VisitParameterClausePackage([NotNull] ParameterClausePackageContext context) {
            var obj = "( ";
            for (int i = 0; i < context.parameter().Length; i++) {
                Parameter p = (Parameter)Visit(context.parameter(i));
                if (i == 0) {
                    obj += $"{p.annotation} {p.type} {p.id} {p.value}";
                } else {
                    obj += $", {p.annotation} {p.type} {p.id} {p.value}";
                }
            }

            obj += " )";
            return obj;
        }

        public override object VisitPackageVariableStatement([NotNull] PackageVariableStatementContext context) {
            var r1 = (Result)Visit(context.expression(0));
            var typ = "";
            Result r2 = null;
            if (context.expression().Length == 2) {
                r2 = (Result)Visit(context.expression(1));
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
                obj += $"{r1.permission} {typ} {r1.text + BlockLeft}";
                var record = new Dictionary<string, bool>();
                foreach (var item in context.packageControlSubStatement()) {
                    var temp = (Visit(item) as Result);
                    obj += temp.text;
                    record[temp.data as string] = true;
                }
                if (r2 != null) {
                    obj = $"protected {typ} _{r1.text} = {r2.text}; {Wrap}" + obj;
                    if (!record.ContainsKey("get")) {
                        obj += $"get {{ return _{r1.text}; }}";
                    }
                    if (r1.isVariable && !record.ContainsKey("set")) {
                        obj += $"set {{ _{r1.text} = value; }}";
                    }
                }
                obj += BlockRight + Wrap;
            } else {
                if (r1.isVariable) {
                    obj += $"{r1.permission} {typ} {r1.text} {{ get;set; }}";
                    if (r2 != null) {
                        obj += $" = {r2.text} {Terminate} {Wrap}";
                    } else {
                        obj += Wrap;
                    }
                } else {
                    obj += $"{r1.permission} readonly {typ} {r1.text}";
                    if (r2 != null) {
                        obj += $" = {r2.text} {Terminate} {Wrap}";
                    } else {
                        obj += Terminate + Wrap;
                    }
                }
            }
            return obj;
        }

        public override object VisitPackageControlSubStatement([NotNull] PackageControlSubStatementContext context) {
            var obj = "";
            var id = "";
            var typ = "";
            (id, typ) = GetControlSub(context.id().GetText());
            if (context.functionSupportStatement().Length > 0) {
                obj += id + BlockLeft;
                foreach (var item in context.functionSupportStatement()) {
                    obj += Visit(item);
                }
                obj += BlockRight + Wrap;
            } else {
                obj += id + Terminate;
            }

            return new Result { text = obj, data = typ };
        }

        public override object VisitPackageFunctionStatement([NotNull] PackageFunctionStatementContext context) {
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
                obj += $"{id.permission} async {pout} {id.text}";
            } else {
                obj += id.permission + " " + Visit(context.parameterClauseOut()) + " " + id.text;
            }

            // 泛型
            if (context.templateDefine() != null) {
                obj += Visit(context.templateDefine());
            }
            obj += Visit(context.parameterClauseIn()) + Wrap + BlockLeft + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += BlockRight + Wrap;
            return obj;
        }

        public override object VisitPackageOverrideFunctionStatement([NotNull] PackageOverrideFunctionStatementContext context) {
            var id = (Result)Visit(context.id());
            var obj = "";
            if (context.annotationSupport() != null) {
                obj += Visit(context.annotationSupport());
            }
            if (context.n != null) {
                obj += "protected ";
            } else {
                obj += $"{id.permission} ";
            }
            // 异步
            if (context.t.Type == FlowRight) {
                var pout = (string)Visit(context.parameterClauseOut());
                if (pout != "void") {
                    pout = $"{Task}<{pout}>";
                } else {
                    pout = Task;
                }
                obj += $"override async {pout} {id.text}";
            } else {
                obj += "override " + Visit(context.parameterClauseOut()) + " " + id.text;
            }

            obj += Visit(context.parameterClauseIn()) + Wrap + BlockLeft + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += BlockRight + Wrap;
            return obj;
        }

        public override object VisitPackageOverrideStatement([NotNull] PackageOverrideStatementContext context) {
            var obj = "";
            foreach (var item in context.packageOverrideFunctionStatement()) {
                obj += Visit(item);
            }
            return obj;
        }

        public override object VisitPackageInitStatement([NotNull] PackageInitStatementContext context) {
            return ProcessFunctionSupport(context.functionSupportStatement());
        }

        public override object VisitProtocolImplementStatement([NotNull] ProtocolImplementStatementContext context) {
            var obj = "";

            var ptcl = (string)Visit(context.nameSpaceItem());
            // 泛型
            if (context.templateCall() != null) {
                ptcl += Visit(context.templateCall());
            }

            obj += $":{ptcl} {Wrap} {BlockLeft} {Wrap}";

            foreach (var item in context.protocolImplementSupportStatement()) {
                obj += Visit(item);
            }
            obj += $"{BlockRight} {Terminate} {Wrap}";
            return obj;
        }

        public override object VisitImplementEventStatement([NotNull] ImplementEventStatementContext context) {
            var obj = "";
            var id = (Result)Visit(context.id());
            var nameSpace = Visit(context.nameSpaceItem());
            obj += $"public event {nameSpace} {id.text + Terminate + Wrap}";
            return obj;
        }

        public override object VisitImplementControlStatement([NotNull] ImplementControlStatementContext context) {
            var r1 = (Result)Visit(context.expression(0));
            var typ = "";
            Result r2 = null;
            if (context.expression().Length == 2) {
                r2 = (Result)Visit(context.expression(1));
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
                obj += $"{r1.permission} {typ} {r1.text + BlockLeft}";
                var record = new Dictionary<string, bool>();
                foreach (var item in context.packageControlSubStatement()) {
                    var temp = (Visit(item) as Result);
                    obj += temp.text;
                    record[temp.data as string] = true;
                }
                if (r2 != null) {
                    obj = $"protected {typ} _{r1.text} = {r2.text}; {Wrap}" + obj;
                    if (!record.ContainsKey("get")) {
                        obj += $"get {{ return _{r1.text}; }}";
                    }
                    if (r1.isVariable && !record.ContainsKey("set")) {
                        obj += $"set {{ _{r1.text} = value; }}";
                    }
                }
                obj += BlockRight + Wrap;
            } else {
                if (r1.isVariable) {
                    obj += $"{r1.permission} {typ} {r1.text} {{ get;set; }}";
                    if (r2 != null) {
                        obj += $" = {r2.text} {Terminate} {Wrap}";
                    } else {
                        obj += Wrap;
                    }
                } else {
                    obj += $"{r1.permission} {typ} {r1.text} {{ get; }}";
                    if (r2 != null) {
                        obj += $" = {r2.text} {Terminate} {Wrap}";
                    } else {
                        obj += Wrap;
                    }
                }
            }
            return obj;
        }

        public override object VisitImplementFunctionStatement([NotNull] ImplementFunctionStatementContext context) {
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
                obj += $"{id.permission} async {pout} {id.text}";
            } else {
                obj += id.permission + " " + Visit(context.parameterClauseOut()) + " " + id.text;
            }

            // 泛型
            if (context.templateDefine() != null) {
                obj += Visit(context.templateDefine());
            }
            obj += Visit(context.parameterClauseIn()) + Wrap + BlockLeft + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += BlockRight + Wrap;
            return obj;
        }

        public override object VisitProtocolStatement([NotNull] ProtocolStatementContext context) {
            var id = (Result)Visit(context.id());
            var obj = "";
            var interfaceProtocol = "";
            var ptclName = id.text;
            if (context.annotationSupport() != null) {
                obj += Visit(context.annotationSupport());
            }
            foreach (var item in context.protocolSupportStatement()) {
                var r = (Result)Visit(item);
                interfaceProtocol += r.text;
            }
            obj += "public partial interface " + ptclName;
            // 泛型
            if (context.templateDefine() != null) {
                obj += Visit(context.templateDefine());
            }
            obj += Wrap + BlockLeft + Wrap;
            obj += interfaceProtocol;
            obj += BlockRight + Wrap;
            return obj;
        }

        public override object VisitProtocolControlStatement([NotNull] ProtocolControlStatementContext context) {
            var id = (Result)Visit(context.id());
            var r = new Result();
            if (context.annotationSupport() != null) {
                r.text += Visit(context.annotationSupport());
            }
            r.permission = "public";

            var type = (string)Visit(context.type());
            r.text += type + " " + id.text;
            if (context.protocolControlSubStatement().Length > 0) {
                r.text += " {";
                foreach (var item in context.protocolControlSubStatement()) {
                    r.text += Visit(item);
                }
                r.text += "}" + Wrap;
            } else {
                if (id.isVariable) {
                    r.text += " { get; set; }" + Wrap;
                } else {
                    r.text += " { get; }" + Wrap;
                }
            }
            return r;
        }

        public override object VisitProtocolControlSubStatement([NotNull] ProtocolControlSubStatementContext context) {
            var obj = "";
            obj = GetControlSub(context.id().GetText()) + Terminate;
            return obj;
        }

        public override object VisitProtocolFunctionStatement([NotNull] ProtocolFunctionStatementContext context) {
            var id = (Result)Visit(context.id());
            var r = new Result();
            if (context.annotationSupport() != null) {
                r.text += Visit(context.annotationSupport());
            }
            r.permission = "public";
            // 异步
            if (context.t.Type == FlowRight) {
                var pout = (string)Visit(context.parameterClauseOut());
                if (pout != "void") {
                    pout = $"{Task}<{pout}>";
                } else {
                    pout = Task;
                }
                r.text += pout + " " + id.text;
            } else {
                r.text += Visit(context.parameterClauseOut()) + " " + id.text;
            }
            // 泛型
            if (context.templateDefine() != null) {
                r.text += Visit(context.templateDefine());
            }
            r.text += Visit(context.parameterClauseIn()) + Terminate + Wrap;
            return r;
        }
    }
}
