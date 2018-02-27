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
            var obj = r1.text + " = " + r2.text + context.Terminate().GetText() + Wrap;
            return obj;
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
            if(count == 2)
            {
                if(context.GetChild(1) is XyParser.ReadElementContext)
                {
                    var ex = (Result)Visit(context.GetChild(0));
                    var read = (string)Visit(context.GetChild(1));
                    r.data = ex.data;
                    r.text = ex.text + read;
                }
            }
            else if(count == 3)
            {
                if(context.GetChild(1).GetType() == typeof(XyParser.CallContext))
                {
                    r.data = "var";
                }
                else if(context.GetChild(1).GetType() == typeof(XyParser.JudgeContext))
                {
                    // todo 如果左右不是bool类型值，报错
                    r.data = "bool";
                }
                else if(context.GetChild(1).GetType() == typeof(XyParser.AddContext))
                {
                    // todo 如果左右不是number或text类型值，报错
                    r.data = "double";
                }
                else if(context.GetChild(1).GetType() == typeof(XyParser.MulContext))
                {
                    // todo 如果左右不是number类型值，报错
                    r.data = "double";
                }
                else if(context.GetChild(1).GetType() == typeof(XyParser.AsContext))
                {
                    var expr = (Result)Visit(context.GetChild(0));
                    var type = (string)Visit(context.GetChild(2));
                    r.data = type;
                    r.text = expr.text + " as " + type;
                    return r;
                }
                else if(context.GetChild(1).GetType() == typeof(XyParser.IsContext))
                {
                    var expr = (Result)Visit(context.GetChild(0));
                    var type = (string)Visit(context.GetChild(2));
                    r.data = "bool";
                    r.text = expr.text + " is " + type;
                    return r;
                }
                var e1 = (Result)Visit(context.GetChild(0));
                var op = Visit(context.GetChild(1));
                var e2 = (Result)Visit(context.GetChild(2));
                r.text = e1.text + op + e2.text;
            }
            else if(count == 1)
            {
                r = (Result)Visit(context.GetChild(0));
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
            r.text += Visit(context.tuple());
            return r;
        }

        public override object VisitCallPkg([NotNull] XyParser.CallPkgContext context)
        {
            var r = new Result();
            r.data = Visit(context.type());
            r.text = "new " + Visit(context.type()) + Visit(context.tuple());
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

        public override object VisitVariableList([NotNull] XyParser.VariableListContext context)
        {
            var newR = new Result();
            var r = (Result)Visit(context.expressionList());
            newR.text += "(" + r.text + ")";
            newR.data = "var";
            return newR;
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

        public override object VisitReadElement([NotNull] XyParser.ReadElementContext context)
        {
            var obj = "";
            foreach(var item in context.expression())
            {
                var r = (Result)Visit(item);
                obj += "[" + r.text + "]";
            }
            return obj;
        }

        public override object VisitDataStatement([NotNull] XyParser.DataStatementContext context)
        {
            var r = new Result();
            if(context.t.Type == XyParser.Number)
            {
                r.data = "double";
                r.text = context.Number().GetText();
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
            r.text += "{" + Visit(context.lambdaOut()) + "}";
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
            foreach(var item in context.functionSupportStatement())
            {
                obj += Visit(item);
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
