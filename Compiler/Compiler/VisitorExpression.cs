using Antlr4.Runtime.Misc;
using Library;
using System.Collections.Generic;
using static Compiler.XsParser;

namespace Compiler {
    internal partial class Visitor {
        public override object VisitVariableStatement(VariableStatementContext context) {
            var obj = "";
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            if (context.type() != null) {
                var Type = (string)Visit(context.type());
                obj = $"{Type} {r1.text} = {r2.text} {Terminate} {Wrap}";
            } else {
                obj = $"var {r1.text} = {r2.text} {Terminate} {Wrap}";
            }
            return obj;
        }

        public override object VisitVariableDeclaredStatement([NotNull] VariableDeclaredStatementContext context) {
            var obj = "";
            var Type = (string)Visit(context.type());
            var r = (Result)Visit(context.expression());
            obj = $"{Type} {r.text} {Terminate} {Wrap}";
            return obj;
        }

        public override object VisitAssignStatement(AssignStatementContext context) {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = r1.text + Visit(context.assign()) + r2.text + Terminate + Wrap;
            return obj;
        }

        public override object VisitAssign([NotNull] AssignContext context) {
            if (context.op.Type == Assign) {
                return "=";
            }
            return context.op.Text;
        }

        public override object VisitExpressionStatement([NotNull] ExpressionStatementContext context) {
            var r = (Result)Visit(context.expression());
            return r.text + Terminate + Wrap;
        }

        public override object VisitExpression([NotNull] ExpressionContext context) {
            var count = context.ChildCount;
            var r = new Result();
            if (count == 3) {
                var e1 = (Result)Visit(context.GetChild(0));
                var op = Visit(context.GetChild(1));

                if (context.GetChild(1).GetType() == typeof(JudgeTypeContext)) {
                    r.data = bl;
                    var e3 = (string)Visit(context.GetChild(2));
                    switch (op) {
                        case "==":
                            r.text = $"({e1.text} is {e3})";
                            break;
                        case "><":
                            r.text = $"!({e1.text} is {e3})";
                            break;
                        default:
                            break;
                    }
                    return r;
                }
                var e2 = (Result)Visit(context.GetChild(2));
                if (context.GetChild(1).GetType() == typeof(JudgeContext)) {
                    // todo 如果左右不是bool类型值，报错
                    r.data = bl;
                } else if (context.GetChild(1).GetType() == typeof(AddContext)) {
                    // todo 如果左右不是number或text类型值，报错
                    if ((string)e1.data == str || (string)e2.data == str) {
                        r.data = str;
                    } else if ((string)e1.data == i32 && (string)e2.data == i32) {
                        r.data = i32;
                    } else {
                        r.data = f64;
                    }
                } else if (context.GetChild(1).GetType() == typeof(MulContext)) {
                    // todo 如果左右不是number类型值，报错
                    if ((string)e1.data == i32 && (string)e2.data == i32) {
                        r.data = i32;
                    } else {
                        r.data = f64;
                    }
                } else if (context.GetChild(1).GetType() == typeof(PowContext)) {
                    // todo 如果左右部署number类型，报错
                    r.data = f64;
                    switch (op) {
                        case "**":
                            op = "Pow";
                            break;
                        case "//":
                            op = "Root";
                            break;
                        case "%%":
                            op = "Log";
                            break;
                        default:
                            break;
                    }
                    r.text = $"{op}({e1.text}, {e2.text})";
                    return r;
                }
                r.text = e1.text + op + e2.text;
            } else if (count == 2) {
                r = (Result)Visit(context.GetChild(0));
                if (context.GetChild(1).GetType() == typeof(TypeConversionContext)) {
                    var e2 = (string)Visit(context.GetChild(1));
                    r.data = e2;
                    r.text = $"To<{e2}>({r.text})";
                } else {
                    if (context.op.Type == XsParser.Judge) {
                        r.text += "?";
                    }
                }
            } else if (count == 1) {
                r = (Result)Visit(context.GetChild(0));
            }
            return r;
        }

        public override object VisitCallBase([NotNull] CallBaseContext context) {
            var r = new Result {
                data = "var"
            };
            var e1 = "base";
            var op = ".";
            var e2 = (Result)Visit(context.GetChild(1));
            r.text = e1 + op + e2.text;
            return r;
        }

        public override object VisitCallSelf([NotNull] CallSelfContext context) {
            var r = new Result {
                data = "var"
            };
            var e1 = "this";
            var op = ".";
            var e2 = (Result)Visit(context.GetChild(1));
            r.text = e1 + op + e2.text;
            return r;
        }

        public override object VisitCallNameSpace([NotNull] CallNameSpaceContext context) {
            var obj = "";
            for (int i = 0; i < context.id().Length; i++) {
                var id = (Result)Visit(context.id(i));
                if (i == 0) {
                    obj += "" + id.text;
                } else {
                    obj += "." + id.text;
                }
            }

            var r = new Result {
                data = "var"
            };
            var e1 = obj;
            var op = ".";
            var e2 = (Result)Visit(context.callExpression());
            r.text = e1 + op + e2.text;
            return r;
        }

        public override object VisitCallExpression([NotNull] CallExpressionContext context) {
            var count = context.ChildCount;
            var r = new Result();
            if (count == 3) {
                var e1 = (Result)Visit(context.GetChild(0));
                var op = Visit(context.GetChild(1));
                var e2 = (Result)Visit(context.GetChild(2));
                r.text = e1.text + op + e2.text;
            } else if (count == 1) {
                r = (Result)Visit(context.GetChild(0));
            }
            return r;
        }

        public override object VisitTypeConversion([NotNull] TypeConversionContext context) {
            return (string)Visit(context.type());
        }

        public override object VisitCall([NotNull] CallContext context) {
            return context.op.Text;
        }

        public override object VisitWave([NotNull] WaveContext context) {
            return context.op.Text;
        }

        public override object VisitJudgeType([NotNull] JudgeTypeContext context) {
            return context.op.Text;
        }

        public override object VisitJudge([NotNull] JudgeContext context) {
            if (context.op.Text == "><") {
                return "!=";
            } else if (context.op.Text == "&") {
                return "&&";
            } else if (context.op.Text == "|") {
                return "||";
            }
            return context.op.Text;
        }

        public override object VisitAdd([NotNull] AddContext context) => context.op.Text;

        public override object VisitMul([NotNull] MulContext context) => context.op.Text;

        public override object VisitPow([NotNull] PowContext context) => context.op.Text;

        public override object VisitPrimaryExpression([NotNull] PrimaryExpressionContext context) {
            if (context.ChildCount == 1) {
                var c = context.GetChild(0);
                if (c is DataStatementContext) {
                    return Visit(context.dataStatement());
                } else if (c is IdContext) {
                    return Visit(context.id());
                } else if (context.t.Type == Self) {
                    return new Result { text = "this", data = "var" };
                } else if (context.t.Type == Discard) {
                    return new Result { text = "_", data = "var" };
                }
            } else if (context.ChildCount == 2) {
                var id = Visit(context.id()).@as<Result>();
                var template = Visit(context.templateCall()).@as<string>();
                return new Result { text = id.text + template, data = id.text + template };
            }
            var r = (Result)Visit(context.expression());
            return new Result { text = "(" + r.text + ")", data = r.data };
        }

        public override object VisitExpressionList([NotNull] ExpressionListContext context) {
            var r = new Result();
            var obj = "";
            for (int i = 0; i < context.expression().Length; i++) {
                var temp = (Result)Visit(context.expression(i));
                if (i == 0) {
                    obj += temp.text;
                } else {
                    obj += ", " + temp.text;
                }
            }
            r.text = obj;
            r.data = "var";
            return r;
        }

        public class TemplateItem {
            public string Template { get; set; }
            public string Contract { get; set; }
        }

        public override object VisitTemplateDefine([NotNull] TemplateDefineContext context) {
            var item = new TemplateItem();
            item.Template += "<";
            for (int i = 0; i < context.templateDefineItem().Length; i++) {
                if (i > 0) {
                    item.Template += ",";
                    if (item.Contract.len() > 0) {
                        item.Contract += ",";
                    }
                }
                var r = (TemplateItem)Visit(context.templateDefineItem(i));
                item.Template += r.Template;
                item.Contract += r.Contract;
            }
            item.Template += ">";
            return item;
        }

        public override object VisitTemplateDefineItem([NotNull] TemplateDefineItemContext context) {
            var item = new TemplateItem();
            if (context.id().len() == 1) {
                var id1 = context.id(0).GetText();
                item.Template = id1;
            } else {
                var id1 = context.id(0).GetText();
                item.Template = id1;
                var id2 = context.id(1).GetText();
                item.Contract = $" where {id1}:{id2}";
            }
            return item;
        }

        public override object VisitTemplateCall([NotNull] TemplateCallContext context) {
            var obj = "";
            obj += "<";
            for (int i = 0; i < context.type().Length; i++) {
                if (i > 0) {
                    obj += ",";
                }
                var r = Visit(context.type(i));
                obj += r;
            }
            obj += ">";
            return obj;
        }

        public override object VisitCallElement([NotNull] CallElementContext context) {
            var id = (Result)Visit(context.id());
            if (context.op?.Type == XsParser.Judge) {
                id.text += "?";
            }
            if (context.expression() == null) {
                return new Result { text = id.text + (string)Visit(context.slice()) };
            }
            var r = (Result)Visit(context.expression());
            r.text = id.text + "[" + r.text + "]";
            return r;
        }

        public override object VisitSlice([NotNull] SliceContext context) {
            return (string)Visit(context.GetChild(0));
        }

        public override object VisitSliceFull([NotNull] SliceFullContext context) {
            var order = "";
            var attach = "";
            switch (context.op.Text) {
                case "<=":
                    order = "true";
                    attach = "true";
                    break;
                case "<":
                    order = "true";
                    break;
                case ">=":
                    order = "false";
                    attach = "true";
                    break;
                case ">":
                    order = "false";
                    break;
                default:
                    break;
            }
            var expr1 = (Result)Visit(context.expression(0));
            var expr2 = (Result)Visit(context.expression(1));
            return $".slice({expr1.text}, {expr2.text}, {order}, {attach})";
        }

        public override object VisitSliceStart([NotNull] SliceStartContext context) {
            var order = "";
            var attach = "";
            switch (context.op.Text) {
                case "<=":
                    order = "true";
                    attach = "true";
                    break;
                case "<":
                    order = "true";
                    break;
                case ">=":
                    order = "false";
                    attach = "true";
                    break;
                case ">":
                    order = "false";
                    break;
                default:
                    break;
            }
            var expr = (Result)Visit(context.expression());
            return $".slice({expr.text}, null, {order}, {attach})";
        }

        public override object VisitSliceEnd([NotNull] SliceEndContext context) {
            var order = "";
            var attach = "false";
            switch (context.op.Text) {
                case "<=":
                    order = "true";
                    attach = "true";
                    break;
                case "<":
                    order = "true";
                    break;
                case ">=":
                    order = "false";
                    attach = "true";
                    break;
                case ">":
                    order = "false";
                    break;
                default:
                    break;
            }
            var expr = (Result)Visit(context.expression());
            return $".slice(null, {expr.text}, {order}, {attach})";
        }

        public override object VisitCallFunc([NotNull] CallFuncContext context) {
            var r = new Result {
                data = "var"
            };
            var id = (Result)Visit(context.id());
            r.text += id.text;
            if (context.templateCall() != null) {
                r.text += Visit(context.templateCall());
            }
            r.text += ((Result)Visit(context.tuple())).text;
            return r;
        }

        public override object VisitCallPkg([NotNull] CallPkgContext context) {
            var r = new Result {
                data = Visit(context.type())
            };
            r.text = $"(new {Visit(context.type())}()";
            if (context.pkgAssign() != null) {
                r.text += Visit(context.pkgAssign());
            }
            if (context.listAssign() != null) {
                r.text += Visit(context.listAssign());
            }
            if (context.dictionaryAssign() != null) {
                r.text += Visit(context.dictionaryAssign());
            }
            r.text += ")";
            return r;
        }

        public override object VisitCallNew([NotNull] CallNewContext context) {
            var r = new Result {
                data = Visit(context.type())
            };
            var param = "";
            if (context.expressionList() != null) {
                param = ((Result)Visit(context.expressionList())).text;
            }
            r.text = $"(new {Visit(context.type())}({param})";
            r.text += ")";
            return r;
        }

        public override object VisitPkgAssign([NotNull] PkgAssignContext context) {
            var obj = "";
            obj += "{";
            for (int i = 0; i < context.pkgAssignElement().Length; i++) {
                if (i == 0) {
                    obj += Visit(context.pkgAssignElement(i));
                } else {
                    obj += "," + Visit(context.pkgAssignElement(i));
                }
            }
            obj += "}";
            return obj;
        }

        public override object VisitListAssign([NotNull] ListAssignContext context) {
            var obj = "";
            obj += "{";
            for (int i = 0; i < context.expression().Length; i++) {
                var r = (Result)Visit(context.expression(i));
                if (i == 0) {
                    obj += r.text;
                } else {
                    obj += "," + r.text;
                }
            }
            obj += "}";
            return obj;
        }

        public override object VisitDictionaryAssign([NotNull] DictionaryAssignContext context) {
            var obj = "";
            obj += "{";
            for (int i = 0; i < context.dictionaryElement().Length; i++) {
                var r = (DicEle)Visit(context.dictionaryElement(i));
                if (i == 0) {
                    obj += r.text;
                } else {
                    obj += "," + r.text;
                }
            }
            obj += "}";
            return obj;
        }

        public override object VisitPkgAssignElement([NotNull] PkgAssignElementContext context) {
            var obj = "";
            obj += Visit(context.name()) + " = " + ((Result)Visit(context.expression())).text;
            return obj;
        }

        public override object VisitPkgAnonymous([NotNull] PkgAnonymousContext context) {
            var r = new Result {
                data = "var",
                text = "new" + (string)Visit(context.pkgAnonymousAssign())
            };
            return r;
        }

        public override object VisitPkgAnonymousAssign([NotNull] PkgAnonymousAssignContext context) {
            var obj = "";
            obj += "{";
            for (int i = 0; i < context.pkgAnonymousAssignElement().Length; i++) {
                if (i == 0) {
                    obj += Visit(context.pkgAnonymousAssignElement(i));
                } else {
                    obj += "," + Visit(context.pkgAnonymousAssignElement(i));
                }
            }
            obj += "}";
            return obj;
        }

        public override object VisitPkgAnonymousAssignElement([NotNull] PkgAnonymousAssignElementContext context) {
            var obj = "";
            obj += Visit(context.name()) + " = " + ((Result)Visit(context.expression())).text;
            return obj;
        }

        public override object VisitCallAwait([NotNull] CallAwaitContext context) {
            var r = new Result();
            var expr = (Result)Visit(context.expression());
            r.data = "var";
            r.text = "await " + expr.text;
            return r;
        }

        public override object VisitList([NotNull] ListContext context) {
            var type = "object";
            var result = new Result();
            for (int i = 0; i < context.expression().Length; i++) {
                var r = (Result)Visit(context.expression(i));
                if (i == 0) {
                    type = (string)r.data;
                    result.text += r.text;
                } else {
                    if (type != (string)r.data) {
                        type = "object";
                    }
                    result.text += "," + r.text;
                }
            }
            result.data = $"{lst}<{type}>";
            result.text = $"(new {result.data}(){{ {result.text} }})";
            return result;
        }

        public override object VisitDictionary([NotNull] DictionaryContext context) {
            var key = Any;
            var value = Any;
            var result = new Result();
            for (int i = 0; i < context.dictionaryElement().Length; i++) {
                var r = (DicEle)Visit(context.dictionaryElement(i));
                if (i == 0) {
                    key = r.key;
                    value = r.value;
                    result.text += r.text;
                } else {
                    if (key != r.key) {
                        key = Any;
                    }
                    if (value != r.value) {
                        value = Any;
                    }
                    result.text += "," + r.text;
                }
            }
            var type = key + "," + value;
            result.data = $"{dic}<{type}>";
            result.text = $"(new {result.data}(){{ {result.text} }})";
            return result;
        }

        private class DicEle {
            public string key;
            public string value;
            public string text;
        }

        public override object VisitDictionaryElement([NotNull] DictionaryElementContext context) {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var result = new DicEle {
                key = (string)r1.data,
                value = (string)r2.data,
                text = "{" + r1.text + "," + r2.text + "}"
            };
            return result;
        }

        public override object VisitStringExpression([NotNull] StringExpressionContext context) {
            var text = $"(new System.Text.StringBuilder({context.Text().GetText()})";
            foreach (var item in context.stringExpressionElement()) {
                text += Visit(item);
            }
            text += ")";
            return new Result {
                data = str,
                text = text,
            };
        }

        public override object VisitStringExpressionElement([NotNull] StringExpressionElementContext context) {
            var r = (Result)Visit(context.expression());
            var text = context.Text().GetText();
            return $".Append({r.text}).Append({text})";
        }

        public override object VisitDataStatement([NotNull] DataStatementContext context) {
            var r = new Result();
            if (context.nil() != null) {
                r.data = Any;
                r.text = "null";
            } else if (context.floatExpr() != null) {
                r.data = f64;
                r.text = (string)Visit(context.floatExpr());
            } else if (context.integerExpr() != null) {
                r.data = i32;
                r.text = (string)Visit(context.integerExpr());
            } else if (context.t.Type == Text) {
                r.data = str;
                r.text = context.Text().GetText();
            } else if (context.t.Type == XsParser.Char) {
                r.data = chr;
                r.text = context.Char().GetText();
            } else if (context.t.Type == XsParser.True) {
                r.data = bl;
                r.text = t;
            } else if (context.t.Type == XsParser.False) {
                r.data = bl;
                r.text = f;
            }
            return r;
        }

        public override object VisitFloatExpr([NotNull] FloatExprContext context) {
            var number = "";
            number += Visit(context.integerExpr(0)) + "." + Visit(context.integerExpr(1));
            return number;
        }

        public override object VisitIntegerExpr([NotNull] IntegerExprContext context) {
            var number = "";
            foreach (var item in context.Number()) {
                number += item.GetText();
            }
            return number;
        }

        public override object VisitFunctionExpression([NotNull] FunctionExpressionContext context) {
            var r = new Result();
            // 异步
            if (context.t.Type == FlowRight) {
                r.text += " async ";
            }
            r.text += Visit(context.anonymousParameterClauseIn()) + " => " + BlockLeft + Wrap;
            r.text += ProcessFunctionSupport(context.functionSupportStatement());
            r.text += BlockRight + Wrap;
            r.data = "var";
            return r;
        }

        public override object VisitAnonymousParameterClauseIn([NotNull] AnonymousParameterClauseInContext context) {
            var obj = "(";

            var lastType = "";
            var temp = new List<string>();
            for (int i = context.parameter().Length - 1; i >= 0; i--) {
                Parameter p = (Parameter)Visit(context.parameter(i));
                if (p.type != null) {
                    lastType = p.type;
                } else {
                    p.type = lastType;
                }

                temp.Add($"{p.annotation} {p.type} {p.id}");
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

        public override object VisitLambda([NotNull] LambdaContext context) {
            var r = new Result {
                data = "var"
            };
            // 异步
            if (context.t.Type == FlowRight) {
                r.text += "async ";
            }
            r.text += "(";
            if (context.lambdaIn() != null) {
                r.text += Visit(context.lambdaIn());
            }
            r.text += ")";
            r.text += "=>";

            if (context.expressionList() != null) {
                r.text += ((Result)Visit(context.expressionList())).text;
            } else {
                r.text += "{" + ProcessFunctionSupport(context.functionSupportStatement()) + "}";
            }

            return r;
        }

        public override object VisitLambdaIn([NotNull] LambdaInContext context) {
            var obj = "";
            for (int i = 0; i < context.id().Length; i++) {
                var r = (Result)Visit(context.id(i));
                if (i == 0) {
                    obj += r.text;
                } else {
                    obj += ", " + r.text;
                }
            }
            return obj;
        }

        public override object VisitPlusMinus([NotNull] PlusMinusContext context) {
            var r = new Result();
            var expr = (Result)Visit(context.expression());
            var op = Visit(context.add());
            r.data = expr.data;
            r.text = op + expr.text;
            return r;
        }

        public override object VisitNegate([NotNull] NegateContext context) {
            var r = new Result();
            var expr = (Result)Visit(context.expression());
            r.data = expr.data;
            r.text = "!" + expr.text;
            return r;
        }

        private readonly List<string> keywords = new List<string> {
                        "abstract", "as", "base", "bool", "break" , "byte", "case" , "catch",
                        "char","checked","class","const","continue","decimal","default","delegate","do","double","else",
                        "enum","event","explicit","extern","false","finally","fixed","float","for","foreach","goto",
                        "if","implicit","in","int","interface","internal","is","lock","long","namespace","new","null",
                        "object","operator","out","override","params","private","protected","public","readonly","ref",
                        "return","sbyte","sealed","short","sizeof","stackalloc","static","string","struct","switch",
                        "this","throw","true","try","typeof","uint","ulong","unchecked","unsafe","ushort","using",
                        "virtual","void","volatile","while"
                };
    }
}