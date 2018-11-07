using Antlr4.Runtime.Misc;
using System;
using System.Collections.Generic;
using System.Text;
using static Compiler.XsParser;

namespace Compiler
{
    internal partial class Visitor
    {
        public override object VisitFunctionStatement([NotNull] FunctionStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = "";
            // 异步
            if (context.t.Type == FlowRight)
            {
                var pout = (string)Visit(context.parameterClauseOut());
                if (pout != "void")
                {
                    pout = $"{Task}<{pout}>";
                }
                else
                {
                    pout = Task;
                }
                obj += $" async {pout} {id.text}";
            }
            else
            {
                obj += Visit(context.parameterClauseOut()) + " " + id.text;
            }
            // 泛型
            if (context.templateDefine() != null)
            {
                obj += Visit(context.templateDefine());
            }
            obj += $"{Visit(context.parameterClauseIn())} {Wrap} {BlockLeft} {Wrap}";
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += BlockRight + Wrap;
            return obj;
        }

        public override object VisitReturnStatement([NotNull] ReturnStatementContext context)
        {
            var r = (Result)Visit(context.tuple());
            if (r.text == "()")
            {
                r.text = "";
            }
            return $"return {r.text} {Terminate} {Wrap}";
        }

        public override object VisitTuple([NotNull] TupleContext context)
        {
            var obj = "(";
            for (int i = 0; i < context.expression().Length; i++)
            {
                var r = (Result)Visit(context.expression(i));
                if (i == 0)
                {
                    obj += r.text;
                }
                else
                {
                    obj += ", " + r.text;
                }
            }
            obj += ")";
            var result = new Result { data = "var", text = obj };
            return result;
        }

        public override object VisitParameterClauseIn([NotNull] ParameterClauseInContext context)
        {
            var obj = "(";

            var lastType = "";
            var temp = new List<string>();
            for (int i = context.parameter().Length - 1; i >= 0; i--)
            {
                Parameter p = (Parameter)Visit(context.parameter(i));
                if (p.type != null)
                {
                    lastType = p.type;
                }
                else
                {
                    p.type = lastType;
                }

                temp.Add($"{p.annotation} {p.type} {p.id}");
            }
            for (int i = temp.Count - 1; i >= 0; i--)
            {
                if (i == temp.Count - 1)
                {
                    obj += temp[i];
                }
                else
                {
                    obj += $", {temp[i]}";
                }
            }

            obj += ")";
            return obj;
        }

        public override object VisitParameterClauseOut([NotNull] ParameterClauseOutContext context)
        {
            var obj = "";
            if (context.parameter().Length == 0)
            {
                obj += "void";
            }
            else if (context.parameter().Length == 1)
            {
                Parameter p = (Parameter)Visit(context.parameter(0));
                obj += p.type;
            }
            if (context.parameter().Length > 1)
            {
                obj += "( ";
                var lastType = "";
                var temp = new List<string>();
                for (int i = context.parameter().Length - 1; i >= 0; i--)
                {
                    Parameter p = (Parameter)Visit(context.parameter(i));
                    if (p.type != null)
                    {
                        lastType = p.type;
                    }
                    else
                    {
                        p.type = lastType;
                    }
                    temp.Add($"{p.annotation} {p.type} {p.id}");
                }
                for (int i = temp.Count - 1; i >= 0; i--)
                {
                    if (i == temp.Count - 1)
                    {
                        obj += temp[i];
                    }
                    else
                    {
                        obj += $", {temp[i]}";
                    }
                }
                obj += " )";
            }
            return obj;
        }

        public class Parameter
        {
            public string id { get; set; }
            public string type { get; set; }
            public string annotation { get; set; }
            public string permission { get; set; }
        }

        public override object VisitParameter([NotNull] ParameterContext context)
        {
            var p = new Parameter();
            var id = (Result)Visit(context.id());
            p.id = id.text;
            p.permission = id.permission;
            if (context.annotation() != null)
            {
                p.annotation = (string)Visit(context.annotation());
            }
            if (context.type() != null)
            {
                p.type = (string)Visit(context.type());
            }

            return p;
        }

        public override object VisitParameterSelf([NotNull] ParameterSelfContext context)
        {
            var p = new Parameter();
            var id = (Result)Visit(context.id());
            p.id = id.text;
            p.permission = id.permission;
            if (context.annotation() != null)
            {
                p.annotation = (string)Visit(context.annotation());
            }
            if (context.type() != null)
            {
                p.type = (string)Visit(context.type());
            }

            return p;
        }

        private class Lazy
        {
            public bool isDefer { get; set; }
            public string content { get; set; }

            public Lazy(bool isDefer, string content)
            {
                this.isDefer = isDefer;
                this.content = content;
            }
        }

        private Stack<Handle> stackHandle = new Stack<Handle>();

        public string ProcessFunctionSupport(FunctionSupportStatementContext[] items)
        {
            var obj = "";
            var content = "";
            var lazy = new List<Lazy>();
            var handleCount = 0;
            foreach (var item in items)
            {
                if (item.GetChild(0) is CheckDeferStatementContext)
                {
                    lazy.Add(new Lazy(true, (string)Visit(item)));
                    content += $"try {Wrap} {{";
                }
                else if (item.GetChild(0) is VariableUseStatementContext)
                {
                    lazy.Add(new Lazy(false, "}"));
                    content += $"using ({(string)Visit(item)}) {{ {Wrap}";
                }
                else if (item.GetChild(0) is HandleStatementContext)
                {
                    stackHandle.Push(Visit(item) as Handle);
                    handleCount += 1;
                }
                else
                {
                    content += Visit(item);
                }
            }
            if (lazy.Count > 0)
            {
                for (int i = lazy.Count - 1; i >= 0; i--)
                {
                    if (lazy[i].isDefer)
                    {
                        content += $"}} {Wrap} finally {Wrap} {{  {lazy[i].content} }}";
                    }
                    else
                    {
                        content += "}";
                    }
                }
            }
            obj += content;
            // 移除栈
            for (int i = 0; i < handleCount; i++)
            {
                stackHandle.Pop();
            }
            return obj;
        }
    }
}
