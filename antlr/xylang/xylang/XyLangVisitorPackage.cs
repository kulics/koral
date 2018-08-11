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
        public override object VisitExtend([NotNull] XyParser.ExtendContext context)
        {
            var r = new Result();
            r.data = Visit(context.type());
            r.text += "(";
            if(context.expressionList() != null)
            {
                r.text += (Visit(context.expressionList()) as Result).text;
            }
            r.text += ")";
            return r;
        }

        public override object VisitPackageExtensionStatement([NotNull] XyParser.PackageExtensionStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = "";
            obj += $"{id.permission} partial class {id.text} {BlockLeft} {Wrap}";
            foreach (var item in context.packageExtensionSupportStatement())
            {
                obj += Visit(item);
            }
            obj += BlockRight + Terminate + Wrap;
            return obj;
        }

        public override object VisitPackageStatement([NotNull] XyParser.PackageStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = "";
            var hasInit = false;
            var extend = "";
            var hasExtend = false;

            if(context.extend() != null)
            {
                extend = (string)((Result)Visit(context.extend())).data;
                hasExtend = true;
            }

            foreach(var item in context.packageSupportStatement())
            {
                if(item.GetChild(0) is XyParser.PackageInitStatementContext)
                {
                    // 处理构造函数
                    if(!hasInit)
                    {
                        obj += "public " + id.text + Visit(context.parameterClausePackage());
                        if(context.extend() != null)
                        {
                            obj += " :base " + ((Result)Visit(context.extend())).text;
                        }
                        obj += Visit(item);
                        hasInit = true;
                    }
                }
                else
                {
                    obj += Visit(item);
                }
            }
            if(!hasInit)
            {
                var init = "public " + id.text + Visit(context.parameterClausePackage());
                if(context.extend() != null)
                {
                    init += " :base " + ((Result)Visit(context.extend())).text;
                }
                obj = init + BlockLeft + BlockRight + obj;
            }
            obj += BlockRight + Terminate + Wrap;
            var header = "";
            if(context.annotation() != null)
            {
                header += Visit(context.annotation());
            }
            header += $"{id.permission} partial class {id.text}";
            // 泛型
            if(context.templateDefine() != null)
            {
                header += Visit(context.templateDefine());
            }
            if(extend.Length > 0)
            {
                header += ":";
                if(extend.Length > 0)
                {
                    header += extend;
                }
            }

            header += Wrap + BlockLeft + Wrap;
            obj = header + obj;
            return obj;
        }

        public override object VisitParameterClausePackage([NotNull] XyParser.ParameterClausePackageContext context)
        {
            var obj = "( ";

            var lastType = "";
            var temp = new List<string>();
            for(int i = context.parameter().Length - 1; i >= 0; i--)
            {
                Parameter p = (Parameter)Visit(context.parameter(i));
                if(p.type != null)
                {
                    lastType = p.type;
                }
                else
                {
                    p.type = lastType;
                }

                temp.Add($"{p.annotation} {p.type} {p.id}");
            }
            for(int i = temp.Count - 1; i >= 0; i--)
            {
                if(i == temp.Count - 1)
                {
                    obj += temp[i];
                }
                else
                {
                    obj += $", {temp[i]}";
                }
            }

            obj += " )";
            return obj;
        }

        public override object VisitPackageVariableStatement([NotNull] XyParser.PackageVariableStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var typ = "";
            if (context.type() != null)
            {
                typ = (string)Visit(context.type());
            }
            else
            {
                var r2 = (Result)Visit(context.expression(1));
                typ = (string)r2.data;
            }
            var obj = "";
            if (context.annotation() != null)
            {
                obj += Visit(context.annotation());
            }
            if (context.packageControlSubStatement().Length > 0)
            {
                obj += $"{r1.permission} {typ} {r1.text + BlockLeft}";
                foreach (var item in context.packageControlSubStatement())
                {
                    obj += Visit(item);
                }
                obj += BlockRight + Wrap;
            }
            else
            {
                obj += $"{r1.permission} {typ} {r1.text +BlockLeft} get;set; {BlockRight+Wrap}";
            }
            if (context.expression(1) != null)
            {
                var r2 = (Result)Visit(context.expression(1));
                obj += $" = {r2.text+Terminate+Wrap}";
            }
            return obj;
        }

        public override object VisitPackageControlSubStatement([NotNull] XyParser.PackageControlSubStatementContext context)
        {
            var obj = "";
            var id = "";
            id = GetControlSub(context.id().GetText());
            if (context.functionSupportStatement().Length>0)
            {
                obj += id + BlockLeft;
                foreach (var item in context.functionSupportStatement())
                {
                    obj += Visit(item);
                }
                obj += BlockRight + Wrap;
            }
            else
            {
                obj += id + Terminate;
            }

            return obj;
        }

        public override object VisitPackageFunctionStatement([NotNull] XyParser.PackageFunctionStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = "";
            if(context.annotation() != null)
            {
                obj += Visit(context.annotation());
            }
            // 异步
            if(context.t.Type == XyParser.FlowRight)
            {
                var pout = (string)Visit(context.parameterClauseOut());
                if(pout != "void")
                {
                    pout = "Task<" + pout + ">";
                }
                else
                {
                    pout = "Task";
                }
                obj += id.permission + " async " + pout + " " + id.text;
            }
            else
            {
                obj += id.permission + " " + Visit(context.parameterClauseOut()) + " " + id.text;
            }

            // 泛型
            if(context.templateDefine() != null)
            {
                obj += Visit(context.templateDefine());
            }
            obj += Visit(context.parameterClauseIn()) + Wrap + BlockLeft + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += BlockRight + Wrap;
            return obj;
        }

        public override object VisitPackageOverrideFunctionStatement([NotNull] XyParser.PackageOverrideFunctionStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = "";
            if(context.annotation() != null)
            {
                obj += Visit(context.annotation());
            }

            obj += "protected override " + Visit(context.parameterClauseOut()) + " " + id.text;

            obj += Visit(context.parameterClauseIn()) + Wrap + BlockLeft + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += BlockRight + Wrap;
            return obj;
        }

        public override object VisitPackageInitStatement([NotNull] XyParser.PackageInitStatementContext context)
        {
            var obj = BlockLeft + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += BlockRight + Wrap;
            return obj;
        }

        public override object VisitProtocolImplementStatement([NotNull] XyParser.ProtocolImplementStatementContext context)
        {
            var id = (Result)Visit(context.id());

            var obj = "";
            obj += id.permission + " partial class " + id.text;

            var ptcl = (string)Visit(context.nameSpaceItem());
            // 泛型
            if(context.templateCall() != null)
            {
                ptcl += Visit(context.templateCall());
            }

            obj += $":{ptcl} {Wrap} {BlockLeft} {Wrap}";

            var pName = ptcl;
            if (pName.LastIndexOf(".") > 0)
            {
                pName = pName.Substring(pName.LastIndexOf("."));
            }
            if (pName.IndexOf("<") > 0)
            {
                pName = pName.Substring(0, pName.LastIndexOf("<"));
            }
            obj += "public " + ptcl + " " + pName +
                " { get { return this as " + ptcl + ";}}" + Wrap;

            foreach(var item in context.protocolImplementSupportStatement())
            {
                if(item.GetChild(0) is XyParser.ImplementFunctionStatementContext)
                {
                    var fn = (Function)Visit(item);
                    obj += fn.@out + " " + ptcl + "." + fn.ID + " " + fn.@in + Wrap + fn.body;
                }
                else if(item.GetChild(0) is XyParser.ImplementControlStatementContext)
                {
                    var vr = (Variable)Visit(item);
                    obj += vr.type + " " + ptcl + "." + vr.ID + " " + vr.body;
                }
                else if(item.GetChild(0) is XyParser.ImplementEventStatementContext)
                {
                    obj += Visit(item);
                }
            }
            obj += $"{BlockRight} {Terminate} {Wrap}";
            return obj;
        }

        public override object VisitImplementEventStatement([NotNull] XyParser.ImplementEventStatementContext context)
        {
            var obj = "";
            var id = (Result)Visit(context.id());
            var nameSpace = Visit(context.nameSpaceItem());
            obj += $"public event {nameSpace} {id.text + Terminate + Wrap}";
            return obj;
        }

        class Variable
        {
            public string type;
            public string ID;
            public string body;
            public string annotation;
        }

        public override object VisitImplementControlStatement([NotNull] XyParser.ImplementControlStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var type = "";
            if (context.type() != null)
            {
                type = (string)Visit(context.type());
            }
            else
            {
                var r2 = (Result)Visit(context.expression());
                type = (string)r2.data;
            }

            var body = "";
            if (context.packageControlSubStatement().Length > 0)
            {
                body += BlockLeft;
                foreach (var item in context.packageControlSubStatement())
                {
                    body += Visit(item);
                }
                body += BlockRight + Wrap;
            }
            else
            {
                body += "{ get; set;}" + Wrap;
            }
            if (context.expression() != null)
            {
                var r2 = (Result)Visit(context.expression());
                body += $" = {r2.text} {Terminate} {Wrap}";
            }

            var vr = new Variable();
            vr.ID = id.text;
            vr.type = type;
            vr.body = body + Wrap;
            if(context.annotation() != null)
            {
                vr.annotation = (string)Visit(context.annotation());
            }
            return vr;
        }

        class Function
        {
            public string ID;
            public string @in;
            public string @out;
            public string body;
            public string annotation;
        }

        public override object VisitImplementFunctionStatement([NotNull] XyParser.ImplementFunctionStatementContext context)
        {
            var fn = new Function();
            var id = (Result)Visit(context.id());
            if(context.annotation() != null)
            {
                fn.annotation = (string)Visit(context.annotation());
            }
            fn.ID = id.text;
            // 泛型
            if(context.templateDefine() != null)
            {
                fn.ID += Visit(context.templateDefine());
            }
            fn.@in = (string)Visit(context.parameterClauseIn());
            // 异步
            if(context.t.Type == XyParser.FlowRight)
            {
                var pout = (string)Visit(context.parameterClauseOut());
                if(pout != "void")
                {
                    pout = "Task<" + pout + ">";
                }
                else
                {
                    pout = "Task";
                }
                fn.@out = " async " + pout;
            }
            else
            {
                fn.@out = (string)Visit(context.parameterClauseOut());
            }
            fn.body = BlockLeft + Wrap;
            fn.body += ProcessFunctionSupport(context.functionSupportStatement());
            fn.body += BlockRight + Wrap;
            return fn;
        }

        public override object VisitProtocolStatement([NotNull] XyParser.ProtocolStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = "";
            var interfaceProtocol = "";
            var ptclName = id.text;
            if(context.annotation() != null)
            {
                obj += Visit(context.annotation());
            }
            foreach(var item in context.protocolSupportStatement())
            {
                var r = (Result)Visit(item);
                interfaceProtocol += r.text;
            }
            obj += "public partial interface " + ptclName;
            // 泛型
            if(context.templateDefine() != null)
            {
                obj += Visit(context.templateDefine());
            }
            obj += Wrap + BlockLeft + Wrap;
            obj += interfaceProtocol;
            obj += BlockRight + Wrap;
            return obj;
        }

        public override object VisitProtocolControlStatement([NotNull] XyParser.ProtocolControlStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var r = new Result();
            if(context.annotation() != null)
            {
                r.text += Visit(context.annotation());
            }
            r.permission = "public";

            var type = (string)Visit(context.type());
            r.text += type + " " + id.text;
            if (context.protocolControlSubStatement().Length >0)
            {
                r.text += " {";
                foreach (var item in context.protocolControlSubStatement())
                {
                    r.text += Visit(item);
                }
                r.text += "}" + Wrap;
            }
            else
            {
                r.text += " { get; set; }" + Wrap;
            }
            return r;
        }

        public override object VisitProtocolControlSubStatement([NotNull] XyParser.ProtocolControlSubStatementContext context)
        {
            var obj = "";
            obj = GetControlSub(context.id().GetText()) + Terminate;
            return obj;
        }

        public override object VisitProtocolFunctionStatement([NotNull] XyParser.ProtocolFunctionStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var r = new Result();
            if(context.annotation() != null)
            {
                r.text += Visit(context.annotation());
            }
            r.permission = "public";
            // 异步
            if(context.t.Type == XyParser.FlowRight)
            {
                var pout = (string)Visit(context.parameterClauseOut());
                if(pout != "void")
                {
                    pout = "Task<" + pout + ">";
                }
                else
                {
                    pout = "Task";
                }
                r.text += pout + " " + id.text;
            }
            else
            {
                r.text += Visit(context.parameterClauseOut()) + " " + id.text;
            }
            // 泛型
            if(context.templateDefine() != null)
            {
                r.text += Visit(context.templateDefine());
            }
            r.text += Visit(context.parameterClauseIn()) + Terminate + Wrap;
            return r;
        }
    }
}
