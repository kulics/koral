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
                    var ptclPre = "";
                    var ptclName = "";
                    var originPtclName = "";
                    if(ptcl.LastIndexOf('.') > 0)
                    {
                        ptclPre = ptcl.Substring(0, ptcl.LastIndexOf('.') + 1);
                        ptclName = ptcl.Substring(ptcl.LastIndexOf('.') + 1);
                        originPtclName = ptclName;
                        if(ptclName.IndexOf('@') >= 0)
                        {
                            ptclName = ptclName.Substring(ptclName.IndexOf('@') + 1);
                        }
                    }
                    else
                    {
                        originPtclName = ptcl;
                        ptclName = ptcl;
                        if(ptclName.IndexOf('@') >= 0)
                        {
                            ptclName = ptclName.Substring(ptclName.IndexOf('@') + 1);
                        }
                    }
                    implements.Add(ptclPre + "Interface" + ptclName);
                    if(originPtclName.IndexOf("<") >= 0)
                    {
                        originPtclName = originPtclName.Substring(0, originPtclName.IndexOf("<"));
                    }
                    obj += "public " + ptclPre + "Interface" + ptclName + " " + originPtclName +
                        " { get { return this as " + ptclPre + "Interface"
                        + ptclName + ";}}" + Wrap;
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
            obj += r1.permission + " " + r2.data + " " + r1.text + " {get;set;} = " + r2.text + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitAnnotation([NotNull] XyParser.AnnotationContext context)
        {
            var obj = "";
            var r = (Result)Visit(context.expressionList());
            obj += "[" + r.text + "]";
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
            var ptclPre = "";
            var ptclName = "";
            var x = ptcl.LastIndexOf('.');
            if(ptcl.LastIndexOf('.') > 0)
            {
                ptclPre = ptcl.Substring(0, ptcl.LastIndexOf('.') + 1);
                ptclName = ptcl.Substring(ptcl.LastIndexOf('.') + 1);
                if(ptclName.IndexOf('@') >= 0)
                {
                    ptclName = ptclName.Substring(ptclName.IndexOf('@') + 1);
                }
            }
            else
            {
                ptclName = ptcl;
                if(ptclName.IndexOf('@') >= 0)
                {
                    ptclName = ptclName.Substring(ptclName.IndexOf('@') + 1);
                }
            }
            // 泛型
            if(context.templateCall() != null)
            {
                ptcl += Visit(context.templateCall());
                ptclName += Visit(context.templateCall());
            }
            var obj = "";
            foreach(var item in context.protocolImplementSupportStatement())
            {
                if(item.GetChild(0) is XyParser.ImplementFunctionStatementContext)
                {
                    var fn = (Function)Visit(item);
                    obj += fn.@out + " " + ptclPre + "Interface" + ptclName + "." + fn.ID + " " + fn.@in + Wrap + fn.body;
                }
                else if(item.GetChild(0) is XyParser.ImplementVariableStatementContext)
                {
                    var vr = (Variable)Visit(item);
                    obj += vr.type + " " + ptclPre + "Interface" + ptclName + "." + vr.ID + " {get;set;} = " + vr.body;
                }
            }
            var r = new Result();
            r.data = ptcl;
            r.text = obj;
            return r;
        }

        class Variable
        {
            public string type;
            public string ID;
            public string body;
        }

        public override object VisitImplementVariableStatement([NotNull] XyParser.ImplementVariableStatementContext context)
        {
            var vr = new Variable();
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            vr.ID = r1.text;
            vr.type = (string)r2.data;
            vr.body = r2.text + context.Terminate().GetText() + Wrap;
            return vr;
        }

        class Function
        {
            public string ID;
            public string @in;
            public string @out;
            public string body;
        }

        public override object VisitImplementFunctionStatement([NotNull] XyParser.ImplementFunctionStatementContext context)
        {
            var fn = new Function();
            var id = (Result)Visit(context.id());
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
            var staticProtocol = "";
            var interfaceProtocol = "";
            var ptclName = id.text;
            if(ptclName.IndexOf('@') >= 0)
            {
                ptclName = ptclName.Substring(ptclName.IndexOf('@') + 1);
            }
            foreach(var item in context.protocolSupportStatement())
            {
                var r = (Result)Visit(item);
                if(r.permission == "public")
                {
                    interfaceProtocol += r.text;
                }
                else
                {
                    staticProtocol += r.text;
                }
            }
            obj += "public partial interface Interface" + ptclName;
            // 泛型
            if(context.templateDefine() != null)
            {
                obj += Visit(context.templateDefine());
            }
            obj += Wrap + context.BlockLeft().GetText() + Wrap;
            obj += interfaceProtocol;
            obj += context.BlockRight().GetText() + Wrap;

            obj += "public static partial class " + id.text;
            // 泛型
            if(context.templateDefine() != null)
            {
                obj += Visit(context.templateDefine());
            }
            obj += Wrap + context.BlockLeft().GetText() + Wrap;
            obj += staticProtocol;
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitProtocolVariableStatement([NotNull] XyParser.ProtocolVariableStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var r = new Result();
            if(r1.permission == "public")
            {
                r.permission = "public";
                r.text += r2.data + " " + r1.text + " {get;set;} " + Wrap;
            }
            else
            {
                r.permission = "private";
                r.text += "public const " + r2.data + " " + r1.text + " = " + r2.text + context.Terminate().GetText() + Wrap;
            }
            return r;
        }

        public override object VisitProtocolFunctionStatement([NotNull] XyParser.ProtocolFunctionStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var r = new Result();
            if(id.permission == "public")
            {
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
            }
            else
            {
                r.permission = "private";
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
                    r.text += "public static async " + pout + " " + id.text;
                }
                else
                {
                    r.text += "public static " + Visit(context.parameterClauseOut()) + " " + id.text;
                }
                // 泛型
                if(context.templateDefine() != null)
                {
                    r.text += Visit(context.templateDefine());
                }
                r.text += Visit(context.parameterClauseIn()) + Wrap + context.BlockLeft().GetText() + Wrap;
                r.text += ProcessFunctionSupport(context.functionSupportStatement());
                r.text += context.BlockRight().GetText() + Wrap;
            }
            return r;
        }
    }
}
