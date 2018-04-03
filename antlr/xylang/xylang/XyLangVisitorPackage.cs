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
        public override object VisitPackageStatement([NotNull] XyParser.PackageStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = "";
            var hasInit = false;
            var extend = "";
            var hasExtend = false;
            var implements = new List<string>();
            foreach(var item in context.packageSupportStatement())
            {
                if(item.GetChild(0) is XyParser.PackageInitStatementContext)
                {
                    // 处理构造函数
                    if(!hasInit)
                    {
                        obj += "public " + id.text + Visit(context.parameterClauseIn());
                        obj += Visit(item);
                        hasInit = true;
                    }
                }
                else if(item.GetChild(0) is XyParser.ProtocolImplementStatementContext)
                {
                    // 处理协议实现
                    var r = (Result)Visit(item);
                    var ptcl = r.data.ToString();
                    implements.Add(ptcl);
                    var pName = ptcl;
                    if(pName.LastIndexOf(".") > 0)
                    {
                        pName = pName.Substring(pName.LastIndexOf("."));
                    }
                    if(pName.IndexOf("<") > 0)
                    {
                        pName = pName.Substring(0, pName.LastIndexOf("<"));
                    }
                    obj += "public " + ptcl + " " + pName +
                        " { get { return this as " + ptcl + ";}}" + Wrap;
                    obj += r.text;
                }
                else if(item.GetChild(0) is XyParser.PackageExtendContext)
                {
                    if(!hasExtend)
                    {
                        extend = (string)Visit(item);
                        hasExtend = true;
                    }
                }
                else
                {
                    obj += Visit(item);
                }
            }
            if(!hasInit)
            {
                obj = "public " + id.text + Visit(context.parameterClauseIn()) + "{}" + obj;
            }
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            var header = "";
            if(context.annotation() != null)
            {
                header += Visit(context.annotation());
            }
            header += id.permission + " partial class " + id.text;
            // 泛型
            if(context.templateDefine() != null)
            {
                header += Visit(context.templateDefine());
            }
            if(implements.Count > 0 || extend.Length > 0)
            {
                header += ":";
                var b = false;
                if(extend.Length > 0)
                {
                    header += extend;
                    b = true;
                }
                for(int i = 0; i < implements.Count; i++)
                {
                    if(i == 0 && !b)
                    {
                        header += implements[i];
                    }
                    else
                    {
                        header += ", " + implements[i];
                    }
                }
            }

            header += Wrap + context.BlockLeft().GetText() + Wrap;
            obj = header + obj;
            return obj;
        }

        public override object VisitPackageVariableStatement([NotNull] XyParser.PackageVariableStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = "";
            if(context.annotation() != null)
            {
                obj += Visit(context.annotation());
            }
            obj += " private " + r2.data + " " + r1.text + " = " + r2.text + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitPackageControlEmptyStatement([NotNull] XyParser.PackageControlEmptyStatementContext context)
        {
            var obj = "";
            if(context.annotation() != null)
            {
                obj += Visit(context.annotation());
            }
            var id = (Result)Visit(context.id());
            var type = (string)Visit(context.type());
            obj += id.permission + " " + type + " " + id.text + "{get;set;}" + Wrap;
            return obj;
        }

        public override object VisitPackageControlStatement([NotNull] XyParser.PackageControlStatementContext context)
        {
            var obj = "";
            if(context.annotation() != null)
            {
                obj += Visit(context.annotation());
            }
            var id = (Result)Visit(context.id());
            var type = (string)Visit(context.type());
            obj += id.permission + " " + type + " " + id.text + "{";
            foreach(var item in context.packageControlSubStatement())
            {
                obj += Visit(item);
            }
            obj += "}" + Wrap;
            return obj;
        }

        public override object VisitPackageControlSubStatement([NotNull] XyParser.PackageControlSubStatementContext context)
        {
            var obj = "";
            var id = "";
            switch(context.op.Text)
            {
                case "=>":
                    id = " get ";
                    break;
                case "<=":
                    id = " set ";
                    break;
                case "+=":
                    id = " add ";
                    break;
                case "-=":
                    id = " remove ";
                    break;
                default:
                    break;
            }
            obj += id + "{";
            foreach(var item in context.functionSupportStatement())
            {
                obj += Visit(item);
            }
            obj += "}" + Wrap;
            return obj;
        }

        public override object VisitPackageExtend([NotNull] XyParser.PackageExtendContext context)
        {
            var pkg = (string)Visit(context.nameSpace()); ;
            return pkg;
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
            if(context.t.Type == XyParser.FunctionAsync)
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
            obj += Visit(context.parameterClauseIn()) + Wrap + context.BlockLeft().GetText() + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitPackageInitStatement([NotNull] XyParser.PackageInitStatementContext context)
        {
            var obj = context.BlockLeft().GetText() + Wrap;
            obj += ProcessFunctionSupport(context.functionSupportStatement());
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitProtocolImplementStatement([NotNull] XyParser.ProtocolImplementStatementContext context)
        {
            var ptcl = (string)Visit(context.nameSpace());
            // 泛型
            if(context.templateCall() != null)
            {
                ptcl += Visit(context.templateCall());
            }
            var obj = "";
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
                else if(item.GetChild(0) is XyParser.ImplementControlEmptyStatementContext)
                {
                    var vr = (Variable)Visit(item);
                    obj += vr.type + " " + ptcl + "." + vr.ID + " " + vr.body;
                }
            }
            var r = new Result();
            r.data = ptcl;
            r.text = obj;
            return r;
        }

        public override object VisitImplementEventStatement([NotNull] XyParser.ImplementEventStatementContext context)
        {
            var obj = "";
            var id = (Result)Visit(context.id());
            var nameSpace = Visit(context.nameSpace());
            obj += "public event " + nameSpace + " " + id.text + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitImplementControlEmptyStatement([NotNull] XyParser.ImplementControlEmptyStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var type = (string)Visit(context.type());

            var vr = new Variable();
            vr.ID = id.text;
            vr.type = type;
            vr.body = "{get;set;}" + Wrap;
            if(context.annotation() != null)
            {
                vr.annotation = (string)Visit(context.annotation());
            }
            return vr;
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
            var type = (string)Visit(context.type());
            var body = "{";
            foreach(var item in context.packageControlSubStatement())
            {
                body += Visit(item);
            }
            body += "}" + Wrap;

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
            if(context.t.Type == XyParser.FunctionAsync)
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
            fn.body = context.BlockLeft().GetText() + Wrap;
            fn.body += ProcessFunctionSupport(context.functionSupportStatement());
            fn.body += context.BlockRight().GetText() + Wrap;
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
            obj += Wrap + context.BlockLeft().GetText() + Wrap;
            obj += interfaceProtocol;
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitProtocolControlEmptyStatement([NotNull] XyParser.ProtocolControlEmptyStatementContext context)
        {
            var r = new Result();
            if(context.annotation() != null)
            {
                r.text += Visit(context.annotation());
            }
            var id = (Result)Visit(context.id());
            var type = (string)Visit(context.type());
            r.text += type + " " + id.text + "{get;set;}" + Wrap;
            return r;
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
            r.text += type + " " + id.text + "{";
            foreach(var item in context.protocolControlSubStatement())
            {
                r.text += Visit(item);
            }
            r.text += "}" + Wrap;
            return r;
        }

        public override object VisitProtocolControlSubStatement([NotNull] XyParser.ProtocolControlSubStatementContext context)
        {
            var obj = "";
            switch(context.op.Text)
            {
                case "=>":
                    obj = "get" + context.Terminate().GetText();
                    break;
                case "<=":
                    obj = "set" + context.Terminate().GetText();
                    break;
                case "+=":
                    obj = "add" + context.Terminate().GetText();
                    break;
                case "-=":
                    obj = "remove" + context.Terminate().GetText();
                    break;
                default:
                    break;
            }
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
            if(context.t.Type == XyParser.FunctionAsync)
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
            r.text += Visit(context.parameterClauseIn()) + context.Terminate().GetText() + Wrap;
            return r;
        }
    }
}
