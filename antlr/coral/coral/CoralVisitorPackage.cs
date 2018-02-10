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
        public override object VisitPackageStatement([NotNull] CoralParser.PackageStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = "";
            var hasInit = false;
            var extend = "";
            var hasExtend = false;
            var implements = new List<string>();
            foreach(var item in context.packageSupportStatement())
            {
                if(item.GetChild(0) is CoralParser.PackageInitStatementContext)
                {
                    // 处理构造函数
                    if(!hasInit && !context.parameterClauseIn().IsEmpty)
                    {
                        obj += "public " + id.text + Visit(context.parameterClauseIn());
                        obj += Visit(item);
                        hasInit = true;
                    }
                }
                else if(item.GetChild(0) is CoralParser.ProtocolImplementStatementContext)
                {
                    // 处理协议实现
                    var r = (Result)Visit(item);
                    var ptcl = r.data.ToString();
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
                    implements.Add(ptclPre + "@Interface" + ptclName.Substring(1));
                    obj += "public " + ptclPre + "@Interface" + ptclName.Substring(1) + " " + ptclName +
                        " { get { return this as " + ptclPre + "@Interface"
                        + ptclName.Substring(1) + ";}}" + Wrap;
                    obj += r.text;
                }
                else if(item.GetChild(0) is CoralParser.PackageExtendContext)
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
            obj += context.BlockRight().GetText() + context.Terminate().GetText() + Wrap;
            var header = id.permission + " class " + id.text;
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

        public override object VisitPackageVariableStatement([NotNull] CoralParser.PackageVariableStatementContext context)
        {
            var r1 = (Result)Visit(context.expression(0));
            var r2 = (Result)Visit(context.expression(1));
            var obj = r1.permission + " " + r2.data + " " + r1.text + " {get;set;} = " + r2.text + context.Terminate().GetText() + Wrap;
            return obj;
        }

        public override object VisitPackageExtend([NotNull] CoralParser.PackageExtendContext context)
        {
            var pkg = (string)Visit(context.nameSpace()); ;
            return pkg;
        }

        public override object VisitPackageInitStatement([NotNull] CoralParser.PackageInitStatementContext context)
        {
            var obj = context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.functionSupportStatement())
            {
                obj += Visit(item);
            }
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitProtocolImplementStatement([NotNull] CoralParser.ProtocolImplementStatementContext context)
        {
            var ptcl = (string)Visit(context.nameSpace());
            var ptclPre = "";
            var ptclName = "";
            var x = ptcl.LastIndexOf('.');
            if(ptcl.LastIndexOf('.') > 0)
            {
                ptclPre = ptcl.Substring(0, ptcl.LastIndexOf('.') + 1);
                ptclName = ptcl.Substring(ptcl.LastIndexOf('.') + 1);
            }
            else
            {
                ptclName = ptcl;
            }

            var obj = "";
            foreach(var item in context.protocolImplementSupportStatement())
            {
                if(item.GetChild(0) is CoralParser.ImplementFunctionStatementContext)
                {
                    var fn = (Function)Visit(item);
                    obj += fn.@out + " " + ptclPre + "@Interface" + ptclName.Substring(1) + "." + fn.ID + " " + fn.@in + Wrap + fn.body;
                }
                else if(item.GetChild(0) is CoralParser.ImplementVariableStatementContext)
                {
                    var vr = (Variable)Visit(item);
                    obj += "public " + vr.type + " " + ptclPre + "@Interface" + ptclName.Substring(1) + "." + vr.ID + " {get;set;} = " + vr.body;
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

        public override object VisitImplementVariableStatement([NotNull] CoralParser.ImplementVariableStatementContext context)
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

        public override object VisitImplementFunctionStatement([NotNull] CoralParser.ImplementFunctionStatementContext context)
        {
            var fn = new Function();
            var id = (Result)Visit(context.id());
            fn.ID = id.text;
            fn.@in = (string)Visit(context.parameterClauseIn());
            fn.@out = (string)Visit(context.parameterClauseOut());
            fn.body = context.BlockLeft().GetText() + Wrap;
            foreach(var item in context.functionSupportStatement())
            {
                fn.body += Visit(item);
            }
            fn.body += context.BlockRight().GetText() + Wrap;
            return fn;
        }

        public override object VisitProtocolStatement([NotNull] CoralParser.ProtocolStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var obj = "";
            var staticProtocol = "";
            var interfaceProtocol = "";
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
            obj += "public interface @Interface" + id.text.Substring(1) + Wrap + context.BlockLeft().GetText() + Wrap;
            obj += interfaceProtocol;
            obj += context.BlockRight().GetText() + Wrap;

            obj += "public static class " + id.text + Wrap + context.BlockLeft().GetText() + Wrap;
            obj += staticProtocol;
            obj += context.BlockRight().GetText() + Wrap;
            return obj;
        }

        public override object VisitProtocolVariableStatement([NotNull] CoralParser.ProtocolVariableStatementContext context)
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

        public override object VisitProtocolFunctionStatement([NotNull] CoralParser.ProtocolFunctionStatementContext context)
        {
            var id = (Result)Visit(context.id());
            var r = new Result();
            if(id.permission == "public")
            {
                r.permission = "public";
                r.text += Visit(context.parameterClauseOut()) + id.text
                + Visit(context.parameterClauseIn()) + context.Terminate().GetText() + Wrap;
            }
            else
            {
                r.permission = "private";
                r.text += "public static " + Visit(context.parameterClauseOut()) + id.text
                + Visit(context.parameterClauseIn()) + Wrap + context.BlockLeft().GetText() + Wrap;
                foreach(var item in context.functionSupportStatement())
                {
                    r.text += Visit(item);
                }
                r.text += context.BlockRight().GetText() + Wrap;
            }
            return r;
        }
    }
}