using Antlr4.Runtime.Misc;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace coral
{
    partial class CoralVisitorBase
    {
        public override object VisitVariableStatement([NotNull] CoralParser.VariableStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = "var " + r1.text + " = " + r2.text + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitAssignStatement([NotNull] CoralParser.AssignStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = r1.text + " = " + r2.text + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitExpressionStatement([NotNull] CoralParser.ExpressionStatementContext context)
        {
            var r = (Result)Visit(context.expression());
            return r.text + context.Terminate().GetText() + Wrap;
        }

        public override object VisitExpression([NotNull] CoralParser.ExpressionContext context)
        {
            var count = context.ChildCount;
            var r = new Result();
            if(count == 2)
            {
                if(context.GetChild(0) is CoralParser.IdContext)
                {
                    r.data = "var";
                    var id = (Result)Visit(context.id());
                    r.text = id.text + Visit(context.tuple());
                }
                else if(context.GetChild(1) is CoralParser.ReadElementContext)
                {
                    var ex = (Result)Visit(context.GetChild(0));
                    var read = (string)Visit(context.GetChild(1));
                    r.data = ex.data;
                    r.text = ex.text + read;
                }
            }
            else if(count == 3)
            {
                if(context.GetChild(1).GetType() == typeof(CoralParser.CallContext))
                {
                    r.data = "var";
                }
                else if(context.GetChild(1).GetType() == typeof(CoralParser.JudgeContext))
                {
                    // todo 如果左右不是bool类型值，报错
                    r.data = "bool";
                }
                else if(context.GetChild(1).GetType() == typeof(CoralParser.AddContext))
                {
                    // todo 如果左右不是number或text类型值，报错
                    r.data = "double";
                }
                else if(context.GetChild(1).GetType() == typeof(CoralParser.MulContext))
                {
                    // todo 如果左右不是number类型值，报错
                    r.data = "double";
                }
                else if(context.GetChild(1).GetType() == typeof(CoralParser.WaveContext))
                {
                    r.data = Visit(context.GetChild(0));
                    r.text = "new " + Visit(context.GetChild(0)) + Visit(context.GetChild(2));
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

        public override object VisitCall([NotNull] CoralParser.CallContext context)
        {
            return context.op.Text;
        }

        public override object VisitWave([NotNull] CoralParser.WaveContext context)
        {
            return context.op.Text;
        }

        public override object VisitJudge([NotNull] CoralParser.JudgeContext context)
        {
            return context.op.Text;
        }

        public override object VisitAdd([NotNull] CoralParser.AddContext context)
        {
            return context.op.Text;
        }

        public override object VisitMul([NotNull] CoralParser.MulContext context)
        {
            return context.op.Text;
        }

        public override object VisitPrimaryExpression([NotNull] CoralParser.PrimaryExpressionContext context)
        {
            if(context.ChildCount == 1)
            {
                var c = context.GetChild(0);
                if(c is CoralParser.DataStatementContext)
                {
                    return Visit(context.dataStatement());
                }
                else if(c is CoralParser.IdContext)
                {
                    return Visit(context.id());
                }
                else if(context.t.Type == CoralParser.Self)
                {
                    return new Result { text = "this", data = "var" };
                }
                else if(context.t.Type == CoralParser.Discard)
                {
                    return new Result { text = "_", data = "var" };
                }
            }
            var r = (Result)Visit(context.expression());
            return new Result { text = "(" + r.text + ")", data = r.data };
        }

        public override object VisitExpressionList([NotNull] CoralParser.ExpressionListContext context)
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

        public override object VisitId([NotNull] CoralParser.IdContext context)
        {
            if(context.op.Type == CoralParser.IDPublic)
            {
                return new Result { text = "@" + context.op.Text, data = "double", permission = "public" };
            }
            else
            {
                return new Result { text = "@" + context.op.Text, data = "double", permission = "private" };
            }
        }

        public override object VisitArray([NotNull] CoralParser.ArrayContext context)
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

        public override object VisitDictionary([NotNull] CoralParser.DictionaryContext context)
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

        public override object VisitVariableList([NotNull] CoralParser.VariableListContext context)
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

        public override object VisitDictionaryElement([NotNull] CoralParser.DictionaryElementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var result = new DicEle();
            result.key = (string)r1.data;
            result.value = (string)r2.data;
            result.text = "{" + r1.text + "," + r2.text + "}";
            return result;
        }

        public override object VisitReadElement([NotNull] CoralParser.ReadElementContext context)
        {
            var obj = "";
            foreach(var item in context.expression())
            {
                var r = (Result)Visit(item);
                obj += "[" + r.text + "]";
            }
            return obj;
        }

        public override object VisitDataStatement([NotNull] CoralParser.DataStatementContext context)
        {
            var r = new Result();
            if(context.t.Type == CoralParser.Number)
            {
                r.data = "double";
                r.text = context.Number().GetText();
            }
            else if(context.t.Type == CoralParser.Text)
            {
                r.data = "string";
                r.text = context.Text().GetText();
            }
            else if(context.t.Type == CoralParser.True)
            {
                r.data = "bool";
                r.text = context.True().GetText();
            }
            else if(context.t.Type == CoralParser.False)
            {
                r.data = "bool";
                r.text = context.False().GetText();
            }
            else if(context.t.Type == CoralParser.Nil)
            {
                r.data = "object";
                r.text = "null";
            }
            return r;
        }

        public override object VisitTypeProtocol([NotNull] CoralParser.TypeProtocolContext context)
        {
            var ptcl = (string)Visit(context.nameSpace());
            var ptclPre = "";
            var ptclName = "";
            if(ptcl.LastIndexOf('.') > 0)
            {
                ptclPre = ptcl.Substring(0, ptcl.LastIndexOf('.') + 1);
                ptclName = ptcl.Substring(ptcl.LastIndexOf('.') + 1);
            }
            else
            {
                ptclName = ptcl;
            }
            var obj = ptclPre + "@Interface" + ptclName.Substring(1);
            return obj;
        }

        public override object VisitTypeArray([NotNull] CoralParser.TypeArrayContext context)
        {
            var obj = "";
            obj += " List<" + Visit(context.type()) + "> ";
            return obj;
        }

        public override object VisitTypeDictinary([NotNull] CoralParser.TypeDictinaryContext context)
        {
            var obj = "";
            obj += " Dictionary<" + Visit(context.type(0)) + "," + Visit(context.type(1)) + "> ";
            return obj;
        }

        public override object VisitTypeBasic([NotNull] CoralParser.TypeBasicContext context)
        {
            var obj = "";
            switch(context.t.Type)
            {
                case CoralParser.TypeNumber:
                    obj = "double";
                    break;
                case CoralParser.TypeText:
                    obj = "string";
                    break;
                case CoralParser.TypeBool:
                    obj = "bool";
                    break;
                case CoralParser.TypeAny:
                    obj = "object";
                    break;
                default:
                    obj = "object";
                    break;
            }
            return obj;
        }
    }
}

