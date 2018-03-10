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
        public override object VisitTypeProtocol([NotNull] XyParser.TypeProtocolContext context)
        {
            var ptcl = (string)Visit(context.nameSpace());
            var ptclPre = "";
            var ptclName = "";
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
            var obj = ptclPre + "Interface" + ptclName;
            return obj;
        }

        public override object VisitTypeTuple([NotNull] XyParser.TypeTupleContext context)
        {
            var obj = "";
            obj += "(";
            for(int i = 0; i < context.type().Length; i++)
            {
                if(i == 0)
                {
                    obj += Visit(context.type(i));
                }
                else
                {
                    obj += "," + Visit(context.type(i));
                }
            }
            obj += ")";
            return obj;
        }

        public override object VisitTypeArray([NotNull] XyParser.TypeArrayContext context)
        {
            var obj = "";
            obj += " List<" + Visit(context.type()) + "> ";
            return obj;
        }

        public override object VisitTypeDictinary([NotNull] XyParser.TypeDictinaryContext context)
        {
            var obj = "";
            obj += " Dictionary<" + Visit(context.type(0)) + "," + Visit(context.type(1)) + "> ";
            return obj;
        }

        public override object VisitTypePackage([NotNull] XyParser.TypePackageContext context)
        {
            var obj = "";
            obj += Visit(context.nameSpace());
            if(context.templateCall() != null)
            {
                obj += Visit(context.templateCall());
            }
            return obj;
        }

        public override object VisitTypeFunction([NotNull] XyParser.TypeFunctionContext context)
        {
            var obj = "";
            var @in = (string)Visit(context.typeFunctionParameterClause(0));
            var @out = (string)Visit(context.typeFunctionParameterClause(1));
            if(@out.Length == 0)
            {
                if(@in.Length == 0)
                {
                    obj += "Action";
                }
                else
                {
                    obj += "Action<";
                    obj += @in;
                    obj += ">";
                }
            }
            else
            {
                if(@out.IndexOf(",") >= 0)
                {
                    @out = "(" + @out + ")";
                }
                if(@in.Length == 0)
                {
                    obj += "Func<";
                    obj += @out;
                    obj += ">";
                }
                else
                {
                    obj += "Func<";
                    obj += @in + ", ";
                    obj += @out;
                    obj += ">";
                }
            }
            return obj;
        }

        public override object VisitTypeFunctionParameterClause([NotNull] XyParser.TypeFunctionParameterClauseContext context)
        {
            var obj = "";
            for(int i = 0; i < context.type().Length; i++)
            {
                var r = (string)Visit(context.type(i));
                if(i == 0)
                {
                    obj += r;
                }
                else
                {
                    obj += ", " + r;
                }
            }
            return obj;
        }

        public override object VisitTypeBasic([NotNull] XyParser.TypeBasicContext context)
        {
            var obj = "";
            switch(context.t.Type)
            {
                case XyParser.TypeFloat:
                    obj = "double";
                    break;
                case XyParser.TypeInteger:
                    obj = "int";
                    break;
                case XyParser.TypeText:
                    obj = "string";
                    break;
                case XyParser.TypeBool:
                    obj = "bool";
                    break;
                case XyParser.TypeAny:
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
