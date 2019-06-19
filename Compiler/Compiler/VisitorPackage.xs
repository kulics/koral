"Compiler" {
    "Antlr4/Runtime"
    "Antlr4/Runtime/Misc"
    "System"

    "Compiler" XsParser.
    "Compiler" Compiler Static.
}

(me:XsLangVisitor)(base) VisitPackageFunctionStatement(context: PackageFunctionStatementContext) -> (v: {}) {
    Self := Visit(context.parameterClauseSelf()):(Parameter)
    self ID = Self.id
    id := Visit(context.id()):(Result)
    isVirtual := ""
    ? id.isVirtual {
        isVirtual = " virtual "
    }
    ? Self.value >< () {
        super ID = Self.value
        isVirtual = " override "
    }
    obj := ""

    obj += ""Self.permission" partial class "Self.type""BlockLeft + Wrap""
    # 异步 #
    ? context.n >< () {
        obj += "protected "
    } _ {
        obj += ""id.permission" "
    }
    ? context.t.Type == Right Flow {
        pout := Visit(context.parameterClauseOut()):(Str)
        ? pout >< "void" {
            pout = ""Task"<"pout">"
        } _ {
            pout = Task
        }
        obj += ""isVirtual" async "pout" "id.text""
    } _ {
        obj += ""isVirtual" " Visit(context.parameterClauseOut())" "id.text""
    }
        # 泛型 #
    templateContract := ""
    ? context.templateDefine() >< () {
        template := Visit(context.templateDefine()):(TemplateItem)
        obj += template.Template
        templateContract = template.Contract
    }
    obj += Visit(context.parameterClauseIn()) + templateContract + Wrap + BlockLeft + Wrap
    obj += ProcessFunctionSupport(context.functionSupportStatement())
    obj += BlockRight + Wrap
    obj += BlockRight + Wrap
    self ID = ""
    super ID = ""
    <- (obj)
}

(me:XsLangVisitor)(base) VisitIncludeStatement(context: IncludeStatementContext) -> (v: {}) {
    <- (Visit(context.typeType()))
}

(me:XsLangVisitor)(base) VisitPackageStatement(context: PackageStatementContext) -> (v: {}) {
    id := Visit(context.id()):(Result)
    obj := ""
    extend := ""

    context.packageSupportStatement() @ item {
        ? item.GetChild(0).GetType() == ?(:IncludeStatementContext) {
            ? extend == "" {
                extend += Visit(item)
            } _ {
                extend += "," + Visit(item)
            }
        } _ {
            obj += Visit(item)
        }
    }
    obj += BlockRight + Terminate + Wrap
    header := ""
    ? context.annotationSupport() >< () {
        header += Visit(context.annotationSupport())
    }
    header += ""id.permission" partial class "id.text""
    # 泛型 #
    template := ""
    templateContract := ""
    ? context.templateDefine() >< () {
        item := Visit(context.templateDefine()):(TemplateItem)
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
    <- (obj)
}

(me:XsLangVisitor)(base) VisitPackageVariableStatement(context: PackageVariableStatementContext) -> (v: {}) {
    r1 := Visit(context.id()):(Result)
    isMutable := r1.isVirtual
    typ := ""
    r2: Result = ()
    ? context.expression() >< () {
        r2 = Visit(context.expression()):(Result)
        typ = r2.data:(Str)
    }
    ? context.typeType() >< () {
        typ = Visit(context.typeType()):(Str)
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

(me:XsLangVisitor)(base) VisitPackageControlStatement(context: PackageControlStatementContext) -> (v: {}) {
    r1 := Visit(context.id()):(Result)
    isMutable := True # r1.isVirtual #
    isVirtual := ""
    ? r1.isVirtual {
        isVirtual = " virtual "
    }
    typ := ""
    r2: Result = ()
    ? context.expression() >< () {
        r2 = Visit(context.expression()):(Result)
        typ = r2.data:(Str)
    }
    ? context.typeType() >< () {
        typ = Visit(context.typeType()):(Str)
    }
    obj := ""
    ? context.annotationSupport() >< () {
        obj += Visit(context.annotationSupport())
    }
    ? context.packageControlSubStatement().Length > 0 {
        obj += ""r1.permission" "isVirtual" "typ" "r1.text""BlockLeft""
        record := [Str]Bool{}
        context.packageControlSubStatement() @ item {
            temp := Visit(item):(Result)
            obj += temp.text
            record[temp.data:(Str)] = True
        }
        ? r2 >< () {
            obj = "protected "typ" _"r1.text" = "r2.text"" Terminate " "Wrap"" obj ""
            ? ~record.ContainsKey("get") {
                obj += "get "BlockLeft" return _"r1.text"; "BlockRight""
            }
            ? isMutable & ~record.ContainsKey("set") {
                obj += "set "BlockLeft" _"r1.text" = value"Terminate" "BlockRight""
            }
        }
        obj += BlockRight + Wrap
    } _ {
        ? isMutable {
            obj += ""r1.permission" "isVirtual" "typ" "r1.text" "BlockLeft" get"Terminate"set"Terminate" "BlockRight""
            ? r2 >< () {
                obj += " = "r2.text" "Terminate" "Wrap""
            } _ {
                obj += Wrap
            }
        } _ {
            obj += ""r1.permission" "isVirtual" "typ" "r1.text" "BlockLeft" get"Terminate" "BlockRight""
            ? r2 >< () {
                obj += " = "r2.text" "Terminate" "Wrap""
            } _ {
                obj += Wrap
            }
        }
    }
    <- (obj)
}

(me:XsLangVisitor)(base) VisitPackageControlSubStatement(context: PackageControlSubStatementContext) -> (v: {}) {
    obj := ""
    id := ""
    typ := ""
    (id, typ) = GetControlSub(context.id().GetText())
    ? context.functionSupportStatement().Length > 0 {
        obj += id + BlockLeft
        context.functionSupportStatement() @ item {
            obj += Visit(item)
        }
        obj += BlockRight + Wrap
    } _ {
        obj += id + Terminate
    }

    <- (Result{ text = obj, data = typ })
}

(me:XsLangVisitor)(base) VisitPackageNewStatement(context: PackageNewStatementContext) -> (v: {}) {
    text := ""
    Self := Visit(context.parameterClauseSelf()):(Parameter)
    self ID = Self.id
    text += ""Self.permission" partial class "Self.type""BlockLeft + Wrap""
    text += "public " Self.type " "
    # 获取构造数据 #
    text += Visit(context.parameterClauseIn()):(Str)
    ? context.expressionList() >< () {
        text += ":base(" Visit(context.expressionList()):(Result).text ")"
    }
    text += BlockLeft + ProcessFunctionSupport(context.functionSupportStatement()) + BlockRight + Wrap
    text += BlockRight + Wrap
    self ID = ""
    <- (text)
}

(me:XsLangVisitor)(base) VisitPackageEventStatement(context: PackageEventStatementContext) -> (v: {}) {
    obj := ""
    id := Visit(context.id()):(Result)
    nameSpace := Visit(context.nameSpaceItem())
    obj += "public event "nameSpace" "id.text + Terminate + Wrap""
    <- (obj)
}

(me:XsLangVisitor)(base) VisitProtocolStatement(context: ProtocolStatementContext) -> (v: {}) {
    id := Visit(context.id()):(Result)
    obj := ""
    interfaceProtocol := ""
    ptclName := id.text
    ? context.annotationSupport() >< () {
        obj += Visit(context.annotationSupport())
    }
    context.protocolSupportStatement() @ item {
        r := Visit(item):(Result)
        interfaceProtocol += r.text
    }
    obj += "public partial interface " + ptclName
    # 泛型 #
    templateContract := ""
    ? context.templateDefine() >< () {
        template := Visit(context.templateDefine()):(TemplateItem)
        obj += template.Template
        templateContract = template.Contract
    }
    obj += templateContract + Wrap + BlockLeft + Wrap
    obj += interfaceProtocol
    obj += BlockRight + Wrap
    <- (obj)
}

(me:XsLangVisitor)(base) VisitProtocolControlStatement(context: ProtocolControlStatementContext) -> (v: {}) {
    id := Visit(context.id()):(Result)
    isMutable := id.isVirtual
    r := Result{}
    ? context.annotationSupport() >< () {
        r.text += Visit(context.annotationSupport())
    }
    r.permission = "public"

    type := Visit(context.typeType()):(Str)
    r.text += type + " " + id.text
    ? context.protocolControlSubStatement().Length > 0 {
        r.text += " {"
        context.protocolControlSubStatement() @ item {
            r.text += Visit(item)
        }
        r.text += "}" + Wrap
    } _ {
        ? isMutable {
            r.text += " { get; set; }" + Wrap
        } _ {
            r.text += " { get; }" + Wrap
        }
    }
    <- (r)
}

(me:XsLangVisitor)(base) VisitProtocolControlSubStatement(context: ProtocolControlSubStatementContext) -> (v: {}) {
    obj := ""
    obj = GetControlSub(context.id().GetText()) + Terminate
    <- (obj)
}

(me:XsLangVisitor)(base) VisitProtocolFunctionStatement(context: ProtocolFunctionStatementContext) -> (v: {}) {
    id := Visit(context.id()):(Result)
    r := Result{}
    ? context.annotationSupport() >< () {
        r.text += Visit(context.annotationSupport())
    }
    r.permission = "public"
    # 异步 #
    ? context.t.Type == Right Flow {
        pout := Visit(context.parameterClauseOut()):(Str)
        ? pout >< "void" {
            pout = ""Task"<"pout">"
        } _ {
            pout = Task
        }
        r.text += pout + " " + id.text
    } _ {
        r.text += Visit(context.parameterClauseOut()) + " " + id.text
    }
    # 泛型 #
    templateContract := ""
    ? context.templateDefine() >< () {
        template := Visit(context.templateDefine()):(TemplateItem)
        r.text += template.Template
        templateContract = template.Contract
    }
    r.text += Visit(context.parameterClauseIn()) + templateContract + Terminate + Wrap
    <- (r)
}
