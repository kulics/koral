using Antlr4.Runtime.Misc;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace xylang
{
    partial class XyLangVisitor
    {
        public override object VisitVariableStatement(XyParser.VariableStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = "var " + r1.text + " = " + r2.text + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitAssignStatement(XyParser.AssignStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = r1.text + Visit(context.assign()) + r2.text + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitAssign([NotNull] XyParser.AssignContext context)
        {
            if(context.op.Type == XyParser.Assign)
            {
                return "=";
            }
            return context.op.Text;
        }

        public override object VisitExpressionStatement([NotNull] XyParser.ExpressionStatementContext context)
        {
            var r = (Result)Visit(context.expression());
            return r.text + context.Terminate().GetText() + Wrap;
        }

        public override object VisitExpression([NotNull] XyParser.ExpressionContext context)
        {
            var count = context.ChildCount;
            var r = new Result();
            if(count == 3)
            {
                var e1 = (Result)Visit(context.GetChild(0));
                var op = Visit(context.GetChild(1));
                var e2 = (Result)Visit(context.GetChild(2));
                if(context.GetChild(1).GetType() == typeof(XyParser.CallContext))
                {
                    r.data = "var";
                    if(((Result)Visit(context.GetChild(2))).isIndex)
                    {
                        r.text = e1.text + e2.text;
                        return r;
                    }
                }
                if(context.GetChild(1).GetType() == typeof(XyParser.JudgeContext))
                {
                    // todo 如果左右不是bool类型值，报错
                    r.data = "bool";
                }
                else if(context.GetChild(1).GetType() == typeof(XyParser.AddContext))
                {
                    // todo 如果左右不是number或text类型值，报错
                    if((string)e1.data == "string" || (string)e2.data == "string")
                    {
                        r.data = "string";
                    }
                    else if((string)e1.data == "int" && (string)e2.data == "int")
                    {
                        r.data = "int";
                    }
                    else
                    {
                        r.data = "double";
                    }
                }
                else if(context.GetChild(1).GetType() == typeof(XyParser.MulContext))
                {
                    // todo 如果左右不是number类型值，报错
                    if((string)e1.data == "int" && (string)e2.data == "int")
                    {
                        r.data = "int";
                    }
                    else
                    {
                        r.data = "double";
                    }
                }
                r.text = e1.text + op + e2.text;
            }
            else if(count == 1)
            {
                r = (Result)Visit(context.GetChild(0));
            }
            return r;
        }

        public override object VisitCallExpression([NotNull] XyParser.CallExpressionContext context)
        {
            var count = context.ChildCount;
            var r = new Result();
            if(count == 3)
            {
                var e1 = (Result)Visit(context.GetChild(0));
                var op = Visit(context.GetChild(1));
                var e2 = (Result)Visit(context.GetChild(2));
                if(context.GetChild(0).GetChild(0) is XyParser.CallElementContext)
                {
                    r.isIndex = true;
                }
                if(context.GetChild(2).GetChild(0) is XyParser.CallElementContext)
                {
                    r.isIndex = true;
                    r.text = e1.text + e2.text;
                    return r;
                }
                r.text = e1.text + op + e2.text;
            }
            else if(count == 1)
            {
                r = (Result)Visit(context.GetChild(0));
                if(context.GetChild(0) is XyParser.CallElementContext)
                {
                    r.isIndex = true;
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
            if(context.op.Text == "=")
            {
                return "==";
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
            if(context.ChildCount == 1)
            {
                var c = context.GetChild(0);
                if(c is XyParser.DataStatementContext)
                {
                    return Visit(context.dataStatement());
                }
                else if(c is XyParser.IdContext)
                {
                    return Visit(context.id());
                }
                else if(context.t.Type == XyParser.Self)
                {
                    return new Result { text = "this", data = "var" };
                }
                else if(context.t.Type == XyParser.Discard)
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
            for(int i = 0; i < context.expression().Length; i++)
            {
                var temp = (Result)Visit(context.expression(i));
                if(i == 0)
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
            for(int i = 0; i < context.id().Length; i++)
            {
                if(i > 0)
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
            for(int i = 0; i < context.type().Length; i++)
            {
                if(i > 0)
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
            var r = new Result();
            r.data = "var";
            var id = (Result)Visit(context.id());
            r.text += id.text;
            if(context.templateCall() != null)
            {
                r.text += Visit(context.templateCall());
            }
            r.text += ((Result)Visit(context.tuple())).text;
            return r;
        }

        public override object VisitCallPkg([NotNull] XyParser.CallPkgContext context)
        {
            var r = new Result();
            r.data = Visit(context.type());
            r.text = "new " + Visit(context.type()) + ((Result)Visit(context.tuple())).text;
            if(context.pkgAssign() != null)
            {
                r.text += Visit(context.pkgAssign());
            }
            if(context.arrayAssign() != null)
            {
                r.text += Visit(context.arrayAssign());
            }
            if(context.dictionaryAssign() != null)
            {
                r.text += Visit(context.dictionaryAssign());
            }
            return r;
        }

        public override object VisitPkgAssign([NotNull] XyParser.PkgAssignContext context)
        {
            var obj = "";
            obj += "{";
            for(int i = 0; i < context.pkgAssignElement().Length; i++)
            {
                if(i == 0)
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
            for(int i = 0; i < context.expression().Length; i++)
            {
                var r = (Result)Visit(context.expression(i));
                if(i == 0)
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
            for(int i = 0; i < context.dictionaryElement().Length; i++)
            {
                var r = (DicEle)Visit(context.dictionaryElement(i));
                if(i == 0)
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
            obj += Visit(context.nameSpace()) + " = " + ((Result)Visit(context.expression())).text;
            return obj;
        }

        public override object VisitPackage([NotNull] XyParser.PackageContext context)
        {
            var r = new Result();
            r.data = "var";
            r.text = "new" + (string)Visit(context.pkgAssign());
            return r;
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
            for(int i = 0; i < context.expression().Length; i++)
            {
                var r = (Result)Visit(context.expression(i));
                if(i == 0)
                {
                    type = (string)r.data;
                    result.text += r.text;
                }
                else
                {
                    if(type != (string)r.data)
                    {
                        type = "object";
                    }
                    result.text += "," + r.text;
                }
            }
            result.data = type + "[]";
            result.text = "new []{" + result.text + "}";
            return result;
        }

        public override object VisitArray([NotNull] XyParser.ArrayContext context)
        {
            var type = "object";
            var result = new Result();
            for(int i = 0; i < context.expression().Length; i++)
            {
                var r = (Result)Visit(context.expression(i));
                if(i == 0)
                {
                    type = (string)r.data;
                    result.text += r.text;
                }
                else
                {
                    if(type != (string)r.data)
                    {
                        type = "object";
                    }
                    result.text += "," + r.text;
                }
            }
            result.data = "List<" + type + ">";
            result.text = "new List<" + type + ">(){" + result.text + "}";
            return result;
        }

        public override object VisitDictionary([NotNull] XyParser.DictionaryContext context)
        {
            var key = "object";
            var value = "object";
            var result = new Result();
            for(int i = 0; i < context.dictionaryElement().Length; i++)
            {
                var r = (DicEle)Visit(context.dictionaryElement(i));
                if(i == 0)
                {
                    key = r.key;
                    value = r.value;
                    result.text += r.text;
                }
                else
                {
                    if(key != r.key)
                    {
                        key = "object";
                    }
                    if(value != r.value)
                    {
                        value = "object";
                    }
                    result.text += "," + r.text;
                }
            }
            var type = key + "," + value;
            result.data = "Dictionary<" + type + ">";
            result.text = "new Dictionary<" + type + ">(){" + result.text + "}";
            return result;
        }

        class DicEle
        {
            public string key;
            public string value;
            public string text;
        }

        public override object VisitDictionaryElement([NotNull] XyParser.DictionaryElementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var result = new DicEle();
            result.key = (string)r1.data;
            result.value = (string)r2.data;
            result.text = "{" + r1.text + "," + r2.text + "}";
            return result;
        }

        public override object VisitDataStatement([NotNull] XyParser.DataStatementContext context)
        {
            var r = new Result();
            if(context.t.Type == XyParser.Float)
            {
                r.data = "double";
                r.text = context.Float().GetText();
            }
            else if(context.t.Type == XyParser.Integer)
            {
                r.data = "int";
                r.text = context.Integer().GetText();
            }
            else if(context.t.Type == XyParser.Text)
            {
                r.data = "string";
                r.text = context.Text().GetText();
            }
            else if(context.t.Type == XyParser.True)
            {
                r.data = "bool";
                r.text = context.True().GetText();
            }
            else if(context.t.Type == XyParser.False)
            {
                r.data = "bool";
                r.text = context.False().GetText();
            }
            else if(context.t.Type == XyParser.Nil)
            {
                r.data = "object";
                r.text = "null";
            }
            return r;
        }

        public override object VisitFunction([NotNull] XyParser.FunctionContext context)
        {
            var r = new Result();
            // 异步
            if(context.t.Type == XyParser.FunctionAsync)
            {
                r.text += " async ";
            }
            r.text += Visit(context.parameterClauseIn()) + " => " + context.BlockLeft().GetText() + Wrap;
            r.text += ProcessFunctionSupport(context.functionSupportStatement());
            r.text += context.BlockRight().GetText() + Wrap;
            r.data = "var";
            return r;
        }

        public override object VisitLambda([NotNull] XyParser.LambdaContext context)
        {
            var r = new Result();
            r.data = "var";
            // 异步
            if(context.t.Type == XyParser.FunctionAsync)
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
            for(int i = 0; i < context.id().Length; i++)
            {
                var r = (Result)Visit(context.id(i));
                if(i == 0)
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
            obj += ((Result)Visit(context.expressionList())).text;
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

        List<string> keywords = new List<string> {
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
