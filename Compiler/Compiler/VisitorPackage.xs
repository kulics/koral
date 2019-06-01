\Compiler <- {
    Antlr4\Runtime
    Antlr4\Runtime\Misc
    System

    Compiler.XsParser
    Compiler.Compiler Static
}

XsLangVisitor -> {
} ...XsParserBaseVisitor<{}> {
    VisitPackageExtensionStatement(context: PackageExtensionStatementContext) -> (v: {}) {
        ## 
        id := Visit(context.id()):Result
        obj := ""
        obj += ""id.permission" partial class "id.text""
        # 泛型
        templateContract := ""
        ? context.templateDefine() >< () {
            template := Visit(context.templateDefine()):TemplateItem
            obj += template.Template
            templateContract = template.Contract
        }
        obj += templateContract + BlockLeft + Wrap
        context.packageExtensionSupportStatement() @ item {
            obj += Visit(item)
        }
        obj += BlockRight + Terminate + Wrap
        ##
        <- ("")
    }

    VisitPackageStatement(context: PackageStatementContext) -> (v: {}) {
        id := Visit(context.id()):Result
        obj := ""
        Init := ""
        extend := ""

        ? context.typeType() >< () {
            extend = Visit(context.typeType()):Str
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
        header := ""
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

    VisitParameterClausePackage(context: ParameterClausePackageContext) -> (v: {}) {
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

    VisitPackageVariableStatement(context: PackageVariableStatementContext) -> (v: {}) {
        r1 := Visit(context.id()):Result
        isMutable := r1.isVirtual
        typ := ""
        r2: Result = ()
        ? context.expression() >< () {
            r2 = Visit(context.expression()):Result
            typ = r2.data:Str
        }
        ? context.typeType() >< () {
            typ = Visit(context.typeType()):Str
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

    VisitPackageControlStatement(context: PackageControlStatementContext) -> (v: {}) {
        r1 := Visit(context.id()):Result
        isMutable := True # r1.isVirtual
        isVirtual := ""
        ? r1.isVirtual {
            isVirtual = " virtual "
        }
        typ := ""
        r2: Result = ()
        ? context.expression() >< () {
            r2 = Visit(context.expression()):Result
            typ = r2.data:Str
        }
        ? context.typeType() >< () {
            typ = Visit(context.typeType()):Str
        }
        obj := ""
        ? context.annotationSupport() >< () {
            obj += Visit(context.annotationSupport())
        }
        ? context.packageControlSubStatement().Length > 0 {
            obj += ""r1.permission" "isVirtual" "typ" "r1.text""BlockLeft""
            record := [Str]Bool{}
            context.packageControlSubStatement() @ item {
                temp := Visit(item):Result
                obj += temp.text
                record[temp.data:Str] = True
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

    VisitPackageControlSubStatement(context: PackageControlSubStatementContext) -> (v: {}) {
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

    VisitPackageFunctionStatement(context: PackageFunctionStatementContext) -> (v: {}) {
        id := Visit(context.id()):Result
        isVirtual := ""
        ? id.isVirtual {
            isVirtual = " virtual "
        }
        obj := ""
        ? context.annotationSupport() >< () {
            obj += Visit(context.annotationSupport())
        }
        # 异步
        ? context.t.Type == Right Flow {
            pout := Visit(context.parameterClauseOut()):Str
            ? pout >< "void" {
                pout = ""Task"<"pout">"
            } _ {
                pout = Task
            }
            obj += ""id.permission" "isVirtual" async "pout" "id.text""
        } _ {
            obj += ""id.permission" "isVirtual" "Visit(context.parameterClauseOut())" "id.text""
        }

        # 泛型
        templateContract := ""
        ? context.templateDefine() >< () {
            template := Visit(context.templateDefine()):TemplateItem
            obj += template.Template
            templateContract = template.Contract
        }
        obj += Visit(context.parameterClauseIn()) + templateContract + Wrap + BlockLeft + Wrap
        obj += ProcessFunctionSupport(context.functionSupportStatement())
        obj += BlockRight + Wrap
        <- (obj)
    }

    VisitPackageOverrideFunctionStatement(context: PackageOverrideFunctionStatementContext) -> (v: {}) {
        id := Visit(context.id()):Result
        obj := ""
        ? context.annotationSupport() >< () {
            obj += Visit(context.annotationSupport())
        }
        ? context.n >< () {
            obj += "protected "
        } _ {
            obj += ""id.permission" "
        }
        # 异步
        ? context.t.Type == Right Flow {
            pout := Visit(context.parameterClauseOut()):Str
            ? pout >< "void" {
                pout = ""Task"<"pout">"
            } _ {
                pout = Task
            }
            obj += "override async "pout" "id.text""
        } _ {
            obj += "override " + Visit(context.parameterClauseOut()) + " " + id.text
        }

        obj += Visit(context.parameterClauseIn()) + Wrap + BlockLeft + Wrap
        obj += ProcessFunctionSupport(context.functionSupportStatement())
        obj += BlockRight + Wrap
        <- (obj)
    }

    VisitPackageOverrideStatement(context: PackageOverrideStatementContext) -> (v: {}) {
        obj := ""
        context.packageOverrideFunctionStatement() @ item {
            obj += Visit(item)
        }
        <- (obj)
    }

    VisitPackageNewStatement(context: PackageNewStatementContext) -> (v: {}) {
        text := ""
        # 获取构造数据
        text = Visit(context.parameterClausePackage()):Str
        ? context.expressionList() >< () {
            text += ":base(" Visit(context.expressionList()):Result.text ")"
        }
        text += BlockLeft + ProcessFunctionSupport(context.functionSupportStatement()) + BlockRight + Wrap
        <- (text)
    }

    VisitProtocolImplementStatement(context: ProtocolImplementStatementContext) -> (v: {}) {
        obj := ""

        ptcl := Visit(context.nameSpaceItem()):Str
        # 泛型
        ? context.templateCall() >< () {
            ptcl += Visit(context.templateCall())
        }

        obj += ":"ptcl" "Wrap" "BlockLeft" "Wrap""

        context.protocolImplementSupportStatement() @ item {
            obj += Visit(item)
        }
        obj += ""BlockRight" "Terminate" "Wrap""
        <- (obj)
    }

    VisitImplementEventStatement(context: ImplementEventStatementContext) -> (v: {}) {
        obj := ""
        id := Visit(context.id()):Result
        nameSpace := Visit(context.nameSpaceItem())
        obj += "public event "nameSpace" "id.text + Terminate + Wrap""
        <- (obj)
    }

    VisitImplementControlStatement(context: ImplementControlStatementContext) -> (v: {}) {
        r1 := Visit(context.expression(0)):Result
        isMutable := r1.isVirtual
        isVirtual := ""
        ? r1.isVirtual {
            isVirtual = " virtual "
        }
        typ := ""
        r2: Result = ()
        ? context.expression().Length == 2 {
            r2 = Visit(context.expression(1)):Result
            typ = r2.data:Str
        }
        ? context.typeType() >< () {
            typ = Visit(context.typeType()):Str
        }
        obj := ""
        ? context.annotationSupport() >< () {
            obj += Visit(context.annotationSupport())
        }
        ? context.packageControlSubStatement().Length > 0 {
            obj += ""r1.permission" "isVirtual" "typ" "r1.text + BlockLeft""
            record := [Str]Bool{}
            context.packageControlSubStatement() @ item {
                temp := Visit(item):Result
                obj += temp.text
                record[temp.data:Str] = True
            }
            ? r2 >< () {
                obj = "protected "typ" _"r1.text" = "r2.text""Terminate" "Wrap"" obj ""
                ? ~record.ContainsKey("get") {
                    obj += "get "BlockLeft" return _"r1.text+Terminate+BlockRight""
                }
                ? isMutable & ~record.ContainsKey("set") {
                    obj += "set "BlockLeft" _"r1.text" = value"Terminate+BlockRight""
                }
            }
            obj += BlockRight + Wrap
        } _ {
            ? isMutable {
                obj += ""r1.permission" "isVirtual" "typ" "r1.text" "BlockLeft" get"Terminate"set"Terminate+BlockRight""
                ? r2 >< () {
                    obj += " = "r2.text" "Terminate+Wrap""
                } _ {
                    obj += Wrap
                }
            } _ {
                obj += ""r1.permission" "isVirtual" "typ" "r1.text" "BlockLeft" get"Terminate+BlockRight""
                ? r2 >< () {
                    obj += " = "r2.text" "Terminate+Wrap""
                } _ {
                    obj += Wrap
                }
            }
        }
        <- (obj)
    }

    VisitImplementFunctionStatement(context: ImplementFunctionStatementContext) -> (v: {}) {
        id := Visit(context.id()):Result
        isVirtual := ""
        ? id.isVirtual {
            isVirtual = " virtual "
        }
        obj := ""
        ? context.annotationSupport() >< () {
            obj += Visit(context.annotationSupport())
        }
        # 异步
        ? context.t.Type == Right Flow {
            pout := Visit(context.parameterClauseOut()):Str
            ? pout >< "void" {
                pout = ""Task"<"pout">"
            } _ {
                pout = Task
            }
            obj += ""id.permission" "isVirtual" async "pout" "id.text""
        } _ {
            obj += id.permission + isVirtual + " " + Visit(context.parameterClauseOut()) + " " + id.text
        }

        # 泛型
        templateContract := ""
        ? context.templateDefine() >< () {
            template := Visit(context.templateDefine()):TemplateItem
            obj += template.Template
            templateContract = template.Contract
        }
        obj += Visit(context.parameterClauseIn()) + templateContract + Wrap + BlockLeft + Wrap
        obj += ProcessFunctionSupport(context.functionSupportStatement())
        obj += BlockRight + Wrap
        <- (obj)
    }

    VisitProtocolStatement(context: ProtocolStatementContext) -> (v: {}) {
        id := Visit(context.id()):Result
        obj := ""
        interfaceProtocol := ""
        ptclName := id.text
        ? context.annotationSupport() >< () {
            obj += Visit(context.annotationSupport())
        }
        context.protocolSupportStatement() @ item {
            r := Visit(item):Result
            interfaceProtocol += r.text
        }
        obj += "public partial interface " + ptclName
        # 泛型
        templateContract := ""
        ? context.templateDefine() >< () {
            template := Visit(context.templateDefine()):TemplateItem
            obj += template.Template
            templateContract = template.Contract
        }
        obj += templateContract + Wrap + BlockLeft + Wrap
        obj += interfaceProtocol
        obj += BlockRight + Wrap
        <- (obj)
    }

    VisitProtocolControlStatement(context: ProtocolControlStatementContext) -> (v: {}) {
        id := Visit(context.id()):Result
        isMutable := id.isVirtual
        r := Result{}
        ? context.annotationSupport() >< () {
            r.text += Visit(context.annotationSupport())
        }
        r.permission = "public"

        type := Visit(context.typeType()):Str
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

    VisitProtocolControlSubStatement(context: ProtocolControlSubStatementContext) -> (v: {}) {
        obj := ""
        obj = GetControlSub(context.id().GetText()) + Terminate
        <- (obj)
    }

    VisitProtocolFunctionStatement(context: ProtocolFunctionStatementContext) -> (v: {}) {
        id := Visit(context.id()):Result
        r := Result{}
        ? context.annotationSupport() >< () {
            r.text += Visit(context.annotationSupport())
        }
        r.permission = "public"
        # 异步
        ? context.t.Type == Right Flow {
            pout := Visit(context.parameterClauseOut()):Str
            ? pout >< "void" {
                pout = ""Task"<"pout">"
            } _ {
                pout = Task
            }
            r.text += pout + " " + id.text
        } _ {
            r.text += Visit(context.parameterClauseOut()) + " " + id.text
        }
        # 泛型
        templateContract := ""
        ? context.templateDefine() >< () {
            template := Visit(context.templateDefine()):TemplateItem
            r.text += template.Template
            templateContract = template.Contract
        }
        r.text += Visit(context.parameterClauseIn()) + templateContract + Terminate + Wrap
        <- (r)
    }
}
