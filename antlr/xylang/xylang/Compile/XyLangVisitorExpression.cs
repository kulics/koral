using Antlr4.Runtime.Misc;
using System.Collections.Generic;

namespace XyLang.Compile
{
    internal partial class XyLangVisitor
    {
        public override object VisitVariableUseStatement([NotNull] XyParser.VariableUseStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = $"var {r1.text} = {r2.text}";
            return obj;
        }

        public override object VisitVariableStatement(XyParser.VariableStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = $"var {r1.text} = {r2.text} {Terminate} {Wrap}";
            return obj;
        }

        public override object VisitVariableDeclaredStatement([NotNull] XyParser.VariableDeclaredStatementContext context)
        {
            var obj = "";
            var Type = (string)Visit(context.type());
            var r1 = (Result)Visit(context.expression(0));
            if (context.expression().Length == 2)
            {
                var r2 = (Result)Visit(context.expression(1));
                obj = $"{Type} {r1.text} = {r2.text} {Terminate} {Wrap}";
            }
            else
            {
                obj = $"{Type} {r1.text} {Terminate} {Wrap}";
            }
            return obj;
        }

        public override object VisitAssignStatement(XyParser.AssignStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = r1.text + Visit(context.assign()) + r2.text + Terminate + Wrap;
            return obj;
        }

        public override object VisitAssign([NotNull] XyParser.AssignContext context)
        {
            if (context.op.Type == XyParser.Assign)
            {
                return "=";
            }
            return context.op.Text;
        }

        public override object VisitExpressionStatement([NotNull] XyParser.ExpressionStatementContext context)
        {
            var r = (Result)Visit(context.expression());
            return r.text + Terminate + Wrap;
        }

        public override object VisitExpression([NotNull] XyParser.ExpressionContext context)
        {
            var count = context.ChildCount;
            var r = new Result();
            if (count == 3)
            {
                var e1 = (Result)Visit(context.GetChild(0));
                var op = Visit(context.GetChild(1));
                var e2 = (Result)Visit(context.GetChild(2));
                if (context.GetChild(1).GetType() == typeof(XyParser.CallContext))
                {
                    r.data = "var";
                    for (int i = 0; i < e2.bracketTime; i++)
                    {
                        r.text += "(";
                    }
                    switch (e2.callType)
                    {
                        case "element":
                            r.text = e1.text + e2.text;
                            return r;
                        case "as":
                        case "is":
                            r.data = e2.data;
                            if (e2.isCall)
                            {
                                r.text += e1.text + e2.text;
                            }
                            else
                            {
                                r.text += e1.text + op + e2.text;
                            }
                            return r;
                        default:
                            break;
                    }
                }
                if (context.GetChild(1).GetType() == typeof(XyParser.JudgeContext))
                {
                    // todo 如果左右不是bool类型值，报错
                    r.data = Bool;
                }
                else if (context.GetChild(1).GetType() == typeof(XyParser.AddContext))
                {
                    // todo 如果左右不是number或text类型值，报错
                    if ((string)e1.data == Str || (string)e2.data == Str)
                    {
                        r.data = Str;
                    }
                    else if ((string)e1.data == I32 && (string)e2.data == I32)
                    {
                        r.data = I32;
                    }
                    else
                    {
                        r.data = F64;
                    }
                }
                else if (context.GetChild(1).GetType() == typeof(XyParser.MulContext))
                {
                    // todo 如果左右不是number类型值，报错
                    if ((string)e1.data == I32 && (string)e2.data == I32)
                    {
                        r.data = I32;
                    }
                    else
                    {
                        r.data = I32;
                    }
                }
                r.text = e1.text + op + e2.text;
            }
            else if (count == 1)
            {
                r = (Result)Visit(context.GetChild(0));
            }
            return r;
        }

        public override object VisitCallSelf([NotNull] XyParser.CallSelfContext context)
        {
            var r = new Result
            {
                data = "var"
            };
            var e1 = "this";
            var op = ".";
            var e2 = (Result)Visit(context.GetChild(1));
            for (int i = 0; i < e2.bracketTime; i++)
            {
                r.text += "(";
            }
            switch (e2.callType)
            {
                case "element":
                    r.text = e1 + e2.text;
                    return r;
                case "as":
                case "is":
                    r.data = e2.data;
                    if (e2.isCall)
                    {
                        r.text += e1 + e2.text;
                    }
                    else
                    {
                        r.text += e1 + op + e2.text;
                    }
                    return r;
                default:
                    break;
            }
            r.text = e1 + op + e2.text;
            return r;
        }

        public override object VisitCallNameSpace([NotNull] XyParser.CallNameSpaceContext context)
        {
            var obj = "";
            for (int i = 0; i < context.id().Length; i++)
            {
                var id = (Result)Visit(context.id(i));
                if (i == 0)
                {
                    obj += "" + id.text;
                }
                else
                {
                    obj += "." + id.text;
                }
            }

            var r = new Result
            {
                data = "var"
            };
            var e1 = obj;
            var op = ".";
            var e2 = (Result)Visit(context.callExpression());
            for (int i = 0; i < e2.bracketTime; i++)
            {
                r.text += "(";
            }
            switch (e2.callType)
            {
                case "element":
                    r.text = e1 + e2.text;
                    return r;
                case "as":
                case "is":
                    r.data = e2.data;
                    if (e2.isCall)
                    {
                        r.text += e1 + e2.text;
                    }
                    else
                    {
                        r.text += e1 + op + e2.text;
                    }
                    return r;
                default:
                    break;
            }
            r.text = e1 + op + e2.text;
            return r;
        }

        public override object VisitCallExpression([NotNull] XyParser.CallExpressionContext context)
        {
            var count = context.ChildCount;
            var r = new Result();
            if (count == 3)
            {
                var e1 = (Result)Visit(context.GetChild(0));
                var op = Visit(context.GetChild(1));
                var e2 = (Result)Visit(context.GetChild(2));
                if (context.GetChild(0).GetChild(0) is XyParser.CallElementContext)
                {
                    r.callType = "element";
                }
                r.isCall = e1.isCall;
                r.callType = e1.callType;
                if (e1.bracketTime > 0)
                {
                    r.bracketTime += e1.bracketTime;
                }
                if (context.GetChild(2).GetChild(0) is XyParser.CallElementContext)
                {
                    r.text = e1.text + e2.text;
                    return r;
                }
                else if (context.GetChild(2).GetChild(0) is XyParser.CallAsContext)
                {
                    r.callType = "as";
                    r.data = e2.data;
                    r.text = e1.text + e2.text;
                    r.bracketTime = e1.bracketTime + 1;
                    return r;
                }
                else if (context.GetChild(2).GetChild(0) is XyParser.CallIsContext)
                {
                    r.callType = "is";
                    r.data = e2.data;
                    r.text = e1.text + e2.text;
                    r.bracketTime = e1.bracketTime + 1;
                    return r;
                }
                r.text = e1.text + op + e2.text;
            }
            else if (count == 1)
            {
                r = (Result)Visit(context.GetChild(0));
                if (context.GetChild(0) is XyParser.CallElementContext)
                {
                    r.callType = "element";
                }
                else if (context.GetChild(0) is XyParser.CallAsContext)
                {
                    r.callType = "as";
                    r.bracketTime++;
                    r.isCall = true;
                }
                else if (context.GetChild(0) is XyParser.CallIsContext)
                {
                    r.callType = "is";
                    r.bracketTime++;
                    r.isCall = true;
                }
            }
            return r;
        }

        public override object VisitCall([NotNull] XyParser.CallContext context)
        {
            return context.op.Text;
        }

        public override object VisitWave([NotNull] XyParser.WaveContext context)
        {
            return context.op.Text;
        }

        public override object VisitJudge([NotNull] XyParser.JudgeContext context)
        {
            if (context.op.Text == "~=")
            {
                return "!=";
            }
            else if (context.op.Text == "&")
            {
                return "&&";
            }
            else if (context.op.Text == "|")
            {
                return "||";
            }
            return context.op.Text;
        }

        public override object VisitAdd([NotNull] XyParser.AddContext context)
        {
            return context.op.Text;
        }

        public override object VisitMul([NotNull] XyParser.MulContext context)
        {
            return context.op.Text;
        }

        public override object VisitPrimaryExpression([NotNull] XyParser.PrimaryExpressionContext context)
        {
            if (context.ChildCount == 1)
            {
                var c = context.GetChild(0);
                if (c is XyParser.DataStatementContext)
                {
                    return Visit(context.dataStatement());
                }
                else if (c is XyParser.IdContext)
                {
                    return Visit(context.id());
                }
                else if (context.t.Type == XyParser.Self)
                {
                    return new Result { text = "this", data = "var" };
                }
                else if (context.t.Type == XyParser.Discard)
                {
                    return new Result { text = "_", data = "var" };
                }
            }
            var r = (Result)Visit(context.expression());
            return new Result { text = "(" + r.text + ")", data = r.data };
        }

        public override object VisitExpressionList([NotNull] XyParser.ExpressionListContext context)
        {
            var r = new Result();
            var obj = "";
            for (int i = 0; i < context.expression().Length; i++)
            {
                var temp = (Result)Visit(context.expression(i));
                if (i == 0)
                {
                    obj += temp.text;
                }
                else
                {
                    obj += ", " + temp.text;
                }
            }
            r.text = obj;
            r.data = "var";
            return r;
        }

        public override object VisitTemplateDefine([NotNull] XyParser.TemplateDefineContext context)
        {
            var obj = "";
            obj += "<";
            for (int i = 0; i < context.id().Length; i++)
            {
                if (i > 0)
                {
                    obj += ",";
                }
                var r = (Result)Visit(context.id(i));
                obj += r.text;
            }
            obj += ">";
            return obj;
        }

        public override object VisitTemplateCall([NotNull] XyParser.TemplateCallContext context)
        {
            var obj = "";
            obj += "<";
            for (int i = 0; i < context.type().Length; i++)
            {
                if (i > 0)
                {
                    obj += ",";
                }
                var r = Visit(context.type(i));
                obj += r;
            }
            obj += ">";
            return obj;
        }

        public override object VisitCallElement([NotNull] XyParser.CallElementContext context)
        {
            var r = (Result)Visit(context.expression());
            r.text = "[" + r.text + "]";
            return r;
        }

        public override object VisitCallFunc([NotNull] XyParser.CallFuncContext context)
        {
            var r = new Result
            {
                data = "var"
            };
            var id = (Result)Visit(context.id());
            r.text += id.text;
            if (context.templateCall() != null)
            {
                r.text += Visit(context.templateCall());
            }
            r.text += ((Result)Visit(context.tuple())).text;
            return r;
        }

        public override object VisitCallPkg([NotNull] XyParser.CallPkgContext context)
        {
            var r = new Result
            {
                data = Visit(context.type())
            };
            var param = "";
            if (context.expressionList() != null)
            {
                param = ((Result)Visit(context.expressionList())).text;
            }
            r.text = $"(new {Visit(context.type())}({param})";
            if (context.pkgAssign() != null)
            {
                r.text += Visit(context.pkgAssign());
            }
            if (context.arrayAssign() != null)
            {
                r.text += Visit(context.arrayAssign());
            }
            if (context.dictionaryAssign() != null)
            {
                r.text += Visit(context.dictionaryAssign());
            }
            r.text += ")";
            return r;
        }

        public override object VisitPkgAssign([NotNull] XyParser.PkgAssignContext context)
        {
            var obj = "";
            obj += "{";
            for (int i = 0; i < context.pkgAssignElement().Length; i++)
            {
                if (i == 0)
                {
                    obj += Visit(context.pkgAssignElement(i));
                }
                else
                {
                    obj += "," + Visit(context.pkgAssignElement(i));
                }
            }
            obj += "}";
            return obj;
        }

        public override object VisitArrayAssign([NotNull] XyParser.ArrayAssignContext context)
        {
            var obj = "";
            obj += "{";
            for (int i = 0; i < context.expression().Length; i++)
            {
                var r = (Result)Visit(context.expression(i));
                if (i == 0)
                {
                    obj += r.text;
                }
                else
                {
                    obj += "," + r.text;
                }
            }
            obj += "}";
            return obj;
        }

        public override object VisitDictionaryAssign([NotNull] XyParser.DictionaryAssignContext context)
        {
            var obj = "";
            obj += "{";
            for (int i = 0; i < context.dictionaryElement().Length; i++)
            {
                var r = (DicEle)Visit(context.dictionaryElement(i));
                if (i == 0)
                {
                    obj += r.text;
                }
                else
                {
                    obj += "," + r.text;
                }
            }
            obj += "}";
            return obj;
        }

        public override object VisitPkgAssignElement([NotNull] XyParser.PkgAssignElementContext context)
        {
            var obj = "";
            obj += Visit(context.name()) + " = " + ((Result)Visit(context.expression())).text;
            return obj;
        }

        public override object VisitPkgAnonymous([NotNull] XyParser.PkgAnonymousContext context)
        {
            var r = new Result
            {
                data = "var",
                text = "new" + (string)Visit(context.pkgAnonymousAssign())
            };
            return r;
        }

        public override object VisitPkgAnonymousAssign([NotNull] XyParser.PkgAnonymousAssignContext context)
        {
            var obj = "";
            obj += "{";
            for (int i = 0; i < context.pkgAnonymousAssignElement().Length; i++)
            {
                if (i == 0)
                {
                    obj += Visit(context.pkgAnonymousAssignElement(i));
                }
                else
                {
                    obj += "," + Visit(context.pkgAnonymousAssignElement(i));
                }
            }
            obj += "}";
            return obj;
        }

        public override object VisitPkgAnonymousAssignElement([NotNull] XyParser.PkgAnonymousAssignElementContext context)
        {
            var obj = "";
            obj += Visit(context.name()) + " = " + ((Result)Visit(context.expression())).text;
            return obj;
        }

        public override object VisitCallAwait([NotNull] XyParser.CallAwaitContext context)
        {
            var r = new Result();
            var expr = (Result)Visit(context.expression());
            r.data = "var";
            r.text = "await " + expr.text;
            return r;
        }

        public override object VisitSharpArray([NotNull] XyParser.SharpArrayContext context)
        {
            var type = "var";
            var result = new Result();
            for (int i = 0; i < context.expression().Length; i++)
            {
                var r = (Result)Visit(context.expression(i));
                if (i == 0)
                {
                    type = (string)r.data;
                    result.text += r.text;
                }
                else
                {
                    if (type != (string)r.data)
                    {
                        type = "object";
                    }
                    result.text += "," + r.text;
                }
            }
            if (context.type() != null)
            {
                result.data = $"{(string)Visit(context.type())}[]";
            }
            else
            {
                result.data = type + "[]";
            }

            result.text = $"(new []{{ {result.text} }})";
            return result;
        }

        public override object VisitArray([NotNull] XyParser.ArrayContext context)
        {
            var type = "object";
            var result = new Result();
            for (int i = 0; i < context.expression().Length; i++)
            {
                var r = (Result)Visit(context.expression(i));
                if (i == 0)
                {
                    type = (string)r.data;
                    result.text += r.text;
                }
                else
                {
                    if (type != (string)r.data)
                    {
                        type = "object";
                    }
                    result.text += "," + r.text;
                }
            }
            if (context.type() != null)
            {
                result.data = $"{List}<{(string)Visit(context.type())}>";
            }
            else
            {
                result.data = $"{List}<{type}>";
            }

            result.text = $"(new {result.data}(){{ {result.text} }})";
            return result;
        }

        public override object VisitDictionary([NotNull] XyParser.DictionaryContext context)
        {
            var key = Any;
            var value = Any;
            var result = new Result();
            for (int i = 0; i < context.dictionaryElement().Length; i++)
            {
                var r = (DicEle)Visit(context.dictionaryElement(i));
                if (i == 0)
                {
                    key = r.key;
                    value = r.value;
                    result.text += r.text;
                }
                else
                {
                    if (key != r.key)
                    {
                        key = Any;
                    }
                    if (value != r.value)
                    {
                        value = Any;
                    }
                    result.text += "," + r.text;
                }
            }
            var type = key + "," + value;
            if (context.type().Length > 0)
            {
                result.data = $"{Dictionary}<{(string)Visit(context.type(0))},{(string)Visit(context.type(1))}>";
            }
            else
            {
                result.data = $"{Dictionary}<{type}>";
            }

            result.text = $"(new {result.data}(){{ {result.text} }})";
            return result;
        }

        private class DicEle
        {
            public string key;
            public string value;
            public string text;
        }

        public override object VisitDictionaryElement([NotNull] XyParser.DictionaryElementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var result = new DicEle
            {
                key = (string)r1.data,
                value = (string)r2.data,
                text = "{" + r1.text + "," + r2.text + "}"
            };
            return result;
        }

        public override object VisitDataStatement([NotNull] XyParser.DataStatementContext context)
        {
            var r = new Result();
            if (context.markText() != null)
            {
                r.data = Str;
                r.text = "$" + Visit(context.markText());
            }
            else if (context.t.Type == XyParser.Float)
            {
                r.data = F64;
                r.text = $"{context.Float().GetText()}";
            }
            else if (context.t.Type == XyParser.Integer)
            {
                r.data = I32;
                r.text = $"{context.Integer().GetText()}";
            }
            else if (context.t.Type == XyParser.Text)
            {
                r.data = Str;
                r.text = context.Text().GetText();
            }
            else if (context.t.Type == XyParser.True)
            {
                r.data = Bool;
                r.text = $"{context.True().GetText()}";
            }
            else if (context.t.Type == XyParser.False)
            {
                r.data = Bool;
                r.text = $"{context.False().GetText()}";
            }
            else if (context.t.Type == XyParser.Null)
            {
                r.data = Any;
                r.text = "null";
            }
            return r;
        }

        public override object VisitMarkText([NotNull] XyParser.MarkTextContext context)
        {
            return context.Text().GetText();
        }

        public override object VisitFunction([NotNull] XyParser.FunctionContext context)
        {
            var r = new Result();
            // 异步
            if (context.t.Type == XyParser.FlowRight)
            {
                r.text += " async ";
            }
            r.text += Visit(context.parameterClauseIn()) + " => " + BlockLeft + Wrap;
            r.text += ProcessFunctionSupport(context.functionSupportStatement());
            r.text += BlockRight + Wrap;
            r.data = "var";
            return r;
        }

        public override object VisitLambda([NotNull] XyParser.LambdaContext context)
        {
            var r = new Result
            {
                data = "var"
            };
            // 异步
            if (context.t.Type == XyParser.FlowLeft)
            {
                r.text += "async ";
            }
            r.text += "(" + Visit(context.lambdaIn()) + ")";
            r.text += "=>";
            r.text += "" + Visit(context.lambdaOut()) + "";
            return r;
        }

        public override object VisitLambdaIn([NotNull] XyParser.LambdaInContext context)
        {
            var obj = "";
            for (int i = 0; i < context.id().Length; i++)
            {
                var r = (Result)Visit(context.id(i));
                if (i == 0)
                {
                    obj += r.text;
                }
                else
                {
                    obj += ", " + r.text;
                }
            }
            return obj;
        }

        public override object VisitLambdaOut([NotNull] XyParser.LambdaOutContext context)
        {
            var obj = "";
            if (context.expressionList() != null)
            {
                obj += ((Result)Visit(context.expressionList())).text;
            }
            else
            {
                obj += "{" + ProcessFunctionSupport(context.functionSupportStatement()) + "}";
            }

            return obj;
        }

        public override object VisitEmpty([NotNull] XyParser.EmptyContext context)
        {
            var r = new Result();
            var type = Visit(context.type());
            r.data = type;
            r.text = "default(" + type + ")";
            return r;
        }

        public override object VisitPlusMinus([NotNull] XyParser.PlusMinusContext context)
        {
            var r = new Result();
            var expr = (Result)Visit(context.expression());
            var op = Visit(context.add());
            r.data = expr.data;
            r.text = op + expr.text;
            return r;
        }

        public override object VisitNegate([NotNull] XyParser.NegateContext context)
        {
            var r = new Result();
            var expr = (Result)Visit(context.expression());
            r.data = expr.data;
            r.text = "!" + expr.text;
            return r;
        }

        public override object VisitBasicConvert([NotNull] XyParser.BasicConvertContext context)
        {
            var r = new Result();
            var expr = (Result)Visit(context.expression());
            var type = (string)Visit(context.typeBasic());
            r.data = type;
            r.text = "((" + type + ")" + "(" + expr.text + "))";
            return r;
        }

        private List<string> keywords => new List<string> {   "abstract", "as", "base", "bool", "break" , "byte", "case" , "catch",
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
