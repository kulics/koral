\Compiler <- {
    Antlr4\Runtime
    Antlr4\Runtime\Misc
    System
    Library
    Compiler.XsParser
    Compiler.Compiler Static
}

XsVisitor -> {
} ...XsBaseVisitor<{}> {
    VisitPackageExtensionStatement(context: PackageExtensionStatementContext) -> ({}) {
        ## var id = (Result)Visit(context.id());
        var obj = "";
        //obj += $"{id.permission} partial class {id.text}";
        //// 泛型
        //var templateContract = "";
        //if (context.templateDefine() != null) {
        //    var template = (TemplateItem)Visit(context.templateDefine());
        //    obj += template.Template;
        //    templateContract = template.Contract;
        //}
        //obj += templateContract + BlockLeft + Wrap;
        //foreach (var item in context.packageExtensionSupportStatement()) {
        //    obj += Visit(item);
        //}
        //obj += BlockRight + Terminate + Wrap;
        ##
        <- ("")
    }

    VisitPackageStatement(context: PackageStatementContext) -> ({}) {
        id := Visit(context.id()):Result
        obj := ""
        Init := ""
        extend := ""

        ? context.type() >< () {
            extend = Visit(context.type()):Str
        }

        # 处理构造函数
        context.packageNewStatement() @ item {
            Init += "public " id.text " " Visit(item):Str ""
        }
        context.packageSupportStatement() @ item {
            obj += Visit(item)
        }
        ? context.packageOverrideStatement() >< () {
            obj += Visit(context.packageOverrideStatement()):Str
        }
        obj = Init + obj
        obj += BlockRight + Terminate + Wrap
        header = ""
        ? context.annotationSupport() >< () {
            header += Visit(context.annotationSupport())
        }
        header += ""id.permission" partial class "id.text""
        # 泛型
        template := ""
        templateContract := ""
        ? context.templateDefine() >< () {
            item := Visit(context.templateDefine()):TemplateItem
            template += item.Template
            templateContract = item.Contract
            header += template;
        }

        ? extend.Length > 0 {
            header += ":"
            ? extend.Length > 0 {
                header += extend
            }
        }

        header += templateContract + Wrap + BlockLeft + Wrap
        obj = header + obj

        context.protocolImplementStatement() @ item {
            obj += ""id.permission" partial class "id.text""template" "Visit(item):Str" "Wrap""
        }

        <- (obj)
    }

    VisitParameterClausePackage(context: ParameterClausePackageContext) -> ({}) {
        obj := "( "
        [0 < context.parameter().Length] @ i {
            p := Visit(context.parameter(i)):Parameter
            ? i == 0 {
                obj += ""p.annotation" "p.type" "p.id" "p.value""
            } _ {
                obj += ", "p.annotation" "p.type" "p.id" "p.value""
            }
        }

        obj += " )"
        <- (obj)
    }

    VisitPackageVariableStatement(context: PackageVariableStatementContext) -> ({}) {
        r1 := Visit(context.id()):Result
        isMutable := r1.isVirtual
        typ := ""
        r2: Result
        ? context.expression() >< () {
            r2 = Visit(context.expression()):Result
            typ = r2.data:Str
        }
        ? context.type() >< () {
            typ = Visit(context.type()):Str
        }
        obj := ""
        ? context.annotationSupport() >< () {
            obj += Visit(context.annotationSupport())
        }

        obj += ""r1.permission" "typ" "r1.text""
        ? r2 >< () {
            obj += " = "r2.text" "Terminate" "Wrap""
        } _ {
            obj += Terminate + Wrap
        }
        <- (obj)
    }

    public override object VisitPackageControlStatement( PackageControlStatementContext context) {
        var r1 = (Result)Visit(context.id());
        var isMutable = r1.isVirtual;
        var isVirtual = r1.isVirtual ? " virtual " : "";
        var typ = "";
        Result r2 = null;
        if (context.expression() != null) {
            r2 = (Result)Visit(context.expression());
            typ = (string)r2.data;
        }
        if (context.type() != null) {
            typ = (string)Visit(context.type());
        }
        var obj = "";
        if (context.annotationSupport() != null) {
            obj += Visit(context.annotationSupport());
        }
        if (context.packageControlSubStatement().Length > 0) {
            obj += $"{r1.permission} {isVirtual} {typ} {r1.text + BlockLeft}";
            var record = new Dictionary<string, bool>();
            foreach (var item in context.packageControlSubStatement()) {
                var temp = (Visit(item) as Result);
                obj += temp.text;
                record[temp.data as string] = true;
            }
            if (r2 != null) {
                obj = $"protected {typ} _{r1.text} = {r2.text}; {Wrap}" + obj;
                if (!record.ContainsKey("get")) {
                    obj += $"get {{ return _{r1.text}; }}";
                }
                if (isMutable && !record.ContainsKey("set")) {
                    obj += $"set {{ _{r1.text} = value; }}";
                }
            }
            obj += BlockRight + Wrap;
        } else {
            if (isMutable) {
                obj += $"{r1.permission} {isVirtual} {typ} {r1.text} {{ get;set; }}";
                if (r2 != null) {
                    obj += $" = {r2.text} {Terminate} {Wrap}";
                } else {
                    obj += Wrap;
                }
            } else {
                obj += $"{r1.permission} {isVirtual} {typ} {r1.text} {{ get; }}";
                if (r2 != null) {
                    obj += $" = {r2.text} {Terminate} {Wrap}";
                } else {
                    obj += Wrap;
                }
            }
        }
        return obj;
    }

    public override object VisitPackageControlSubStatement( PackageControlSubStatementContext context) {
        var obj = "";
        var id = "";
        var typ = "";
        (id, typ) = GetControlSub(context.id().GetText());
        if (context.functionSupportStatement().Length > 0) {
            obj += id + BlockLeft;
            foreach (var item in context.functionSupportStatement()) {
                obj += Visit(item);
            }
            obj += BlockRight + Wrap;
        } else {
            obj += id + Terminate;
        }

        return new Result { text = obj, data = typ };
    }

    public override object VisitPackageFunctionStatement( PackageFunctionStatementContext context) {
        var id = (Result)Visit(context.id());
        var isVirtual = id.isVirtual ? " virtual " : "";
        var obj = "";
        if (context.annotationSupport() != null) {
            obj += Visit(context.annotationSupport());
        }
        // 异步
        if (context.t.Type == FlowRight) {
            var pout = (string)Visit(context.parameterClauseOut());
            if (pout != "void") {
                pout = $"{Task}<{pout}>";
            } else {
                pout = Task;
            }
            obj += $"{id.permission} {isVirtual} async {pout} {id.text}";
        } else {
            obj += id.permission + isVirtual + " " + Visit(context.parameterClauseOut()) + " " + id.text;
        }

        // 泛型
        var templateContract = "";
        if (context.templateDefine() != null) {
            var template = (TemplateItem)Visit(context.templateDefine());
            obj += template.Template;
            templateContract = template.Contract;
        }
        obj += Visit(context.parameterClauseIn()) + templateContract + Wrap + BlockLeft + Wrap;
        obj += ProcessFunctionSupport(context.functionSupportStatement());
        obj += BlockRight + Wrap;
        return obj;
    }

    public override object VisitPackageOverrideFunctionStatement( PackageOverrideFunctionStatementContext context) {
        var id = (Result)Visit(context.id());
        var obj = "";
        if (context.annotationSupport() != null) {
            obj += Visit(context.annotationSupport());
        }
        if (context.n != null) {
            obj += "protected ";
        } else {
            obj += $"{id.permission} ";
        }
        // 异步
        if (context.t.Type == FlowRight) {
            var pout = (string)Visit(context.parameterClauseOut());
            if (pout != "void") {
                pout = $"{Task}<{pout}>";
            } else {
                pout = Task;
            }
            obj += $"override async {pout} {id.text}";
        } else {
            obj += "override " + Visit(context.parameterClauseOut()) + " " + id.text;
        }

        obj += Visit(context.parameterClauseIn()) + Wrap + BlockLeft + Wrap;
        obj += ProcessFunctionSupport(context.functionSupportStatement());
        obj += BlockRight + Wrap;
        return obj;
    }

    public override object VisitPackageOverrideStatement( PackageOverrideStatementContext context) {
        var obj = "";
        foreach (var item in context.packageOverrideFunctionStatement()) {
            obj += Visit(item);
        }
        return obj;
    }

    public override object VisitPackageNewStatement( PackageNewStatementContext context) {
        var text = "";
        // 获取构造数据
        text = (string)Visit(context.parameterClausePackage());
        if (context.expressionList() != null) {
            text += ":base(" + (Visit(context.expressionList()) as Result).text + ")" ;
        }
        text += BlockLeft + ProcessFunctionSupport(context.functionSupportStatement()) + BlockRight + Wrap;
        return text;
    }

    public override object VisitProtocolImplementStatement( ProtocolImplementStatementContext context) {
        var obj = "";

        var ptcl = (string)Visit(context.nameSpaceItem());
        // 泛型
        if (context.templateCall() != null) {
            ptcl += Visit(context.templateCall());
        }

        obj += $":{ptcl} {Wrap} {BlockLeft} {Wrap}";

        foreach (var item in context.protocolImplementSupportStatement()) {
            obj += Visit(item);
        }
        obj += $"{BlockRight} {Terminate} {Wrap}";
        return obj;
    }

    public override object VisitImplementEventStatement( ImplementEventStatementContext context) {
        var obj = "";
        var id = (Result)Visit(context.id());
        var nameSpace = Visit(context.nameSpaceItem());
        obj += $"public event {nameSpace} {id.text + Terminate + Wrap}";
        return obj;
    }

    public override object VisitImplementControlStatement( ImplementControlStatementContext context) {
        var r1 = (Result)Visit(context.expression(0));
        var isMutable = r1.isVirtual;
        var isVirtual = r1.isVirtual ? " virtual " : "";
        var typ = "";
        Result r2 = null;
        if (context.expression().Length == 2) {
            r2 = (Result)Visit(context.expression(1));
            typ = (string)r2.data;
        }
        if (context.type() != null) {
            typ = (string)Visit(context.type());
        }
        var obj = "";
        if (context.annotationSupport() != null) {
            obj += Visit(context.annotationSupport());
        }
        if (context.packageControlSubStatement().Length > 0) {
            obj += $"{r1.permission} {isVirtual} {typ} {r1.text + BlockLeft}";
            var record = new Dictionary<string, bool>();
            foreach (var item in context.packageControlSubStatement()) {
                var temp = (Visit(item) as Result);
                obj += temp.text;
                record[temp.data as string] = true;
            }
            if (r2 != null) {
                obj = $"protected {typ} _{r1.text} = {r2.text}; {Wrap}" + obj;
                if (!record.ContainsKey("get")) {
                    obj += $"get {{ return _{r1.text}; }}";
                }
                if (isMutable && !record.ContainsKey("set")) {
                    obj += $"set {{ _{r1.text} = value; }}";
                }
            }
            obj += BlockRight + Wrap;
        } else {
            if (isMutable) {
                obj += $"{r1.permission} {isVirtual} {typ} {r1.text} {{ get;set; }}";
                if (r2 != null) {
                    obj += $" = {r2.text} {Terminate} {Wrap}";
                } else {
                    obj += Wrap;
                }
            } else {
                obj += $"{r1.permission} {isVirtual} {typ} {r1.text} {{ get; }}";
                if (r2 != null) {
                    obj += $" = {r2.text} {Terminate} {Wrap}";
                } else {
                    obj += Wrap;
                }
            }
        }
        return obj;
    }

    public override object VisitImplementFunctionStatement( ImplementFunctionStatementContext context) {
        var id = (Result)Visit(context.id());
        var isVirtual = id.isVirtual ? " virtual " : "";
        var obj = "";
        if (context.annotationSupport() != null) {
            obj += Visit(context.annotationSupport());
        }
        // 异步
        if (context.t.Type == FlowRight) {
            var pout = (string)Visit(context.parameterClauseOut());
            if (pout != "void") {
                pout = $"{Task}<{pout}>";
            } else {
                pout = Task;
            }
            obj += $"{id.permission} {isVirtual} async {pout} {id.text}";
        } else {
            obj += id.permission + isVirtual + " " + Visit(context.parameterClauseOut()) + " " + id.text;
        }

        // 泛型
        var templateContract = "";
        if (context.templateDefine() != null) {
            var template = (TemplateItem)Visit(context.templateDefine());
            obj += template.Template;
            templateContract = template.Contract;
        }
        obj += Visit(context.parameterClauseIn()) + templateContract + Wrap + BlockLeft + Wrap;
        obj += ProcessFunctionSupport(context.functionSupportStatement());
        obj += BlockRight + Wrap;
        return obj;
    }

    public override object VisitProtocolStatement( ProtocolStatementContext context) {
        var id = (Result)Visit(context.id());
        var obj = "";
        var interfaceProtocol = "";
        var ptclName = id.text;
        if (context.annotationSupport() != null) {
            obj += Visit(context.annotationSupport());
        }
        foreach (var item in context.protocolSupportStatement()) {
            var r = (Result)Visit(item);
            interfaceProtocol += r.text;
        }
        obj += "public partial interface " + ptclName;
        // 泛型
        var templateContract = "";
        if (context.templateDefine() != null) {
            var template = (TemplateItem)Visit(context.templateDefine());
            obj += template.Template;
            templateContract = template.Contract;
        }
        obj += templateContract + Wrap + BlockLeft + Wrap;
        obj += interfaceProtocol;
        obj += BlockRight + Wrap;
        return obj;
    }

    public override object VisitProtocolControlStatement( ProtocolControlStatementContext context) {
        var id = (Result)Visit(context.id());
        var isMutable = id.isVirtual;
        var r = new Result();
        if (context.annotationSupport() != null) {
            r.text += Visit(context.annotationSupport());
        }
        r.permission = "public";

        var type = (string)Visit(context.type());
        r.text += type + " " + id.text;
        if (context.protocolControlSubStatement().Length > 0) {
            r.text += " {";
            foreach (var item in context.protocolControlSubStatement()) {
                r.text += Visit(item);
            }
            r.text += "}" + Wrap;
        } else {
            if (isMutable) {
                r.text += " { get; set; }" + Wrap;
            } else {
                r.text += " { get; }" + Wrap;
            }
        }
        return r;
    }

    public override object VisitProtocolControlSubStatement( ProtocolControlSubStatementContext context) {
        var obj = "";
        obj = GetControlSub(context.id().GetText()) + Terminate;
        return obj;
    }

    public override object VisitProtocolFunctionStatement( ProtocolFunctionStatementContext context) {
        var id = (Result)Visit(context.id());
        var r = new Result();
        if (context.annotationSupport() != null) {
            r.text += Visit(context.annotationSupport());
        }
        r.permission = "public";
        // 异步
        if (context.t.Type == FlowRight) {
            var pout = (string)Visit(context.parameterClauseOut());
            if (pout != "void") {
                pout = $"{Task}<{pout}>";
            } else {
                pout = Task;
            }
            r.text += pout + " " + id.text;
        } else {
            r.text += Visit(context.parameterClauseOut()) + " " + id.text;
        }
        // 泛型
        var templateContract = "";
        if (context.templateDefine() != null) {
            var template = (TemplateItem)Visit(context.templateDefine());
            r.text += template.Template;
            templateContract = template.Contract;
        }
        r.text += Visit(context.parameterClauseIn()) + templateContract + Terminate + Wrap;
        return r;
    }
}