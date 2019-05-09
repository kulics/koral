using Antlr4.Runtime.Misc;
using System.Collections.Generic;
using static Compiler.XsParser;

namespace Compiler {
    internal partial class Visitor {
        public override object VisitFunctionStatement([NotNull] FunctionStatementContext context) {
            var id = (Result)Visit(context.id());
            var obj = "";
            // 异步
            if (context.t.Type == FlowRight) {
                var pout = (string)Visit(context.parameterClauseOut());
                if (pout != "void") {
                    pout = $"{Task}<{pout}>";
                } else {
                    pout = Task;
                }
                obj += $" async {pout} {id.text}";
            } else {
                obj += Visit(context.parameterClauseOut()) + " " + id.text;
            }
            // 泛型
            var templateContract = "";
            if (context.templateDefine() != null) {
                var template = (TemplateItem)Visit(context.templateDefine());
                obj += template.Template;
                templateContract = template.Contract;
            }
            obj += $"{Visit(context.parameterClauseIn())} {templateContract} {Wrap} {BlockLeft} {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += BlockRight + Wrap;
            return obj;
        }

        public override object VisitReturnStatement([NotNull] ReturnStatementContext context) {
            var r = (Result)Visit(context.tuple());
            if (r.text == "()") {
                r.text = "";
            }
            return $"return {r.text} {Terminate} {Wrap}";
        }

        public override object VisitTuple([NotNull] TupleContext context) {
            var obj = "(";
            for (int i = 0; i < context.expression().Length; i++) {
                var r = (Result)Visit(context.expression(i));
                if (i == 0) {
                    obj += r.text;
                } else {
                    obj += ", " + r.text;
                }
            }
            obj += ")";
            var result = new Result { data = "var", text = obj };
            return result;
        }

        public override object VisitTupleExpression([NotNull] TupleExpressionContext context) {
            var obj = "(";
            for (int i = 0; i < context.expression().Length; i++) {
                var r = (Result)Visit(context.expression(i));
                if (i == 0) {
                    obj += r.text;
                } else {
                    obj += ", " + r.text;
                }
            }
            obj += ")";
            var result = new Result { data = "var", text = obj };
            return result;
        }

        public override object VisitParameterClauseIn([NotNull] ParameterClauseInContext context) {
            var obj = "(";
            var temp = new List<string>();
            for (int i = context.parameter().Length - 1; i >= 0; i--) {
                Parameter p = (Parameter)Visit(context.parameter(i));
                temp.Add($"{p.annotation} {p.type} {p.id} {p.value}");
            }
            for (int i = temp.Count - 1; i >= 0; i--) {
                if (i == temp.Count - 1) {
                    obj += temp[i];
                } else {
                    obj += $", {temp[i]}";
                }
            }

            obj += ")";
            return obj;
        }

        public override object VisitParameterClauseOut([NotNull] ParameterClauseOutContext context) {
            var obj = "";
            if (context.parameter().Length == 0) {
                obj += "void";
            } else if (context.parameter().Length == 1) {
                Parameter p = (Parameter)Visit(context.parameter(0));
                obj += p.type;
            }
            if (context.parameter().Length > 1) {
                obj += "( ";
                var temp = new List<string>();
                for (int i = context.parameter().Length - 1; i >= 0; i--) {
                    Parameter p = (Parameter)Visit(context.parameter(i));
                    temp.Add($"{p.annotation} {p.type} {p.id} {p.value}");
                }
                for (int i = temp.Count - 1; i >= 0; i--) {
                    if (i == temp.Count - 1) {
                        obj += temp[i];
                    } else {
                        obj += $", {temp[i]}";
                    }
                }
                obj += " )";
            }
            return obj;
        }

        public class Parameter {
            public string id { get; set; }
            public string type { get; set; }
            public string value { get; set; }
            public string annotation { get; set; }
            public string permission { get; set; }
        }

        public override object VisitParameter([NotNull] ParameterContext context) {
            var p = new Parameter();
            var id = (Result)Visit(context.id());
            p.id = id.text;
            p.permission = id.permission;
            if (context.annotationSupport() != null) {
                p.annotation = (string)Visit(context.annotationSupport());
            }
            if (context.expression() != null) {
                p.value = "=" + (Visit(context.expression()) as Result).text;
            }
            p.type = (string)Visit(context.type());
            return p;
        }

        public string ProcessFunctionSupport(FunctionSupportStatementContext[] items) {
            var obj = "";
            var content = "";
            var lazy = new List<string>();
            foreach (var item in items) {
                if (item.GetChild(0) is UsingStatementContext) {
                    lazy.Add("}");
                    content += $"using ({(string)Visit(item)}) {{ {Wrap}";
                } else {
                    content += Visit(item);
                }
            }
            if (lazy.Count > 0) {
                for (int i = lazy.Count - 1; i >= 0; i--) {
                    content += "}";
                }
            }
            obj += content;
            return obj;
        }
    }
}
