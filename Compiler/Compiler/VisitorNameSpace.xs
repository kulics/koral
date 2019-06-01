\Compiler <- {
    Antlr4\Runtime
    Antlr4\Runtime\Misc
    System

    Compiler.XsParser
    Compiler.Compiler Static
}

Namespace -> {
    name: Str
    imports: Str
}

GetControlSub(id: Str) -> (id: Str, type:Str) {
    typ := ""
    id ? "get" {
        id = " get "
        typ = "get"
    } "set" {
        id = " set "
        typ = "set"
    } "_get" {
        id = " protected get "
        typ = "get"
    } "_set" {
        id = " protected set "
        typ = "set"
    } "add" {
        id = " add "
        typ = "add"
    } "remove" {
        id = " remove "
        typ = "remove"
    }
    <- (id, typ)
}

XsLangVisitor -> {
} ...XsParserBaseVisitor<{}> {
    VisitStatement(context: StatementContext) -> (v: {}) {
        obj := ""
        ns := Visit(context.exportStatement()):Namespace
        # import library
        obj += "using Library;"Wrap"using static Library.Lib;"Wrap""
        obj += ns.imports + Wrap
        ? context.annotationSupport() >< () {
            obj += Visit(context.annotationSupport())
        }
        obj += "namespace "ns.name + Wrap + BlockLeft + Wrap""

        content := ""
        contentStatic := ""
        context.namespaceSupportStatement() @ item {
            type := item.GetChild(0).GetType()
            ? type == ?(:NamespaceVariableStatementContext) | type == ?(:NamespaceControlStatementContext) | type == ?(:NamespaceFunctionStatementContext) | type == ?(:NamespaceConstantStatementContext) {
                contentStatic += Visit(item)
            } _ {
                content += Visit(item)
            }
        }
        obj += content
        ? contentStatic >< "" {
            obj += "public partial class "ns.name.sub Str(ns.name.last index of(".") + 1) "_Static" + BlockLeft + Wrap + contentStatic + BlockRight + Wrap
        }
        obj += BlockRight + Wrap
        <- (obj)
    }

    VisitExportStatement(context: ExportStatementContext) -> (v: {}) {
        obj := Namespace{
            name = Visit(context.nameSpace()):Str
        }
        context.importStatement() @ item {
            obj.imports += Visit(item):Str
        }
        <- (obj)
    }

    VisitImportStatement(context: ImportStatementContext) -> (v: {}) {
        obj := ""
        ? context.annotationSupport() >< () {
            obj += Visit(context.annotationSupport());
        }
        ? context.id() >< () {
            ns := Visit(context.nameSpace()):Str
            obj += "using static " + ns
            ? context.id() >< () {
                r := Visit(context.id()):Result

                obj += "." + r.text
            }

            obj += Terminate
        } _ {
            obj += "using " + Visit(context.nameSpace()) + Terminate
        }
        obj += Wrap
        <- (obj)
    }

    VisitNameSpace(context: NameSpaceContext) -> (v: {}) {
        obj := ""
        [0 < context.id().Length] @ i {
            id := Visit(context.id(i)):Result
            ? i == 0 {
                obj += "" + id.text
            } _ {
                obj += "." + id.text
            }
        }
        <- (obj)
    }

    VisitNameSpaceItem(context: NameSpaceItemContext) -> (v: {}) {
        obj := ""
        [0 < context.id().Length] @ i {
            id := Visit(context.id(i)):Result
            ? i == 0 {
                obj += "" + id.text
            } _ {
                obj += "." + id.text
            }
        }
        <- (obj)
    }

    VisitName(context: NameContext) -> (v: {}) {
        obj := ""
        [0 < context.id().Length] @ i {
            id := Visit(context.id(i)):Result
            ? i == 0 {
                obj += "" + id.text
            } _ {
                obj += "." + id.text
            }
        }
        <- (obj)
    }

    VisitEnumStatement(context: EnumStatementContext) -> (v: {}) {
        obj := ""
        id := Visit(context.id()):Result
        header := ""
        typ := Visit(context.typeType()):Str
        ? context.annotationSupport() >< () {
            header += Visit(context.annotationSupport())
        }
        header += id.permission + " enum " + id.text + ":" + typ
        header += Wrap + BlockLeft + Wrap
        [0 < context.enumSupportStatement().Length] @ i {
            obj += Visit(context.enumSupportStatement(i))
        }
        obj += BlockRight + Terminate + Wrap
        obj = header + obj
        <- (obj)
    }

    VisitEnumSupportStatement(context: EnumSupportStatementContext) -> (v: {}) {
        id := Visit(context.id()):Result
        ? context.integerExpr() >< () {
            op := ""
            ? context.add() >< () {
                op = Visit(context.add()):Str
            }
            id.text += " = " + op + Visit(context.integerExpr())
        }
        <- (id.text + ",")
    }

    VisitNamespaceFunctionStatement(context: NamespaceFunctionStatementContext) -> (v: {}) {
        id := Visit(context.id()):Result
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
            obj += ""id.permission" async static "pout" "id.text""
        } _ {
            obj += ""id.permission" static "Visit(context.parameterClauseOut())" "id.text""
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

    VisitNamespaceConstantStatement(context: NamespaceConstantStatementContext) -> (v: {}) {
        id := Visit(context.id()):Result
        expr := Visit(context.expression()):Result
        typ := "";
        ? context.typeType() >< () {
            typ = Visit(context.typeType()):Str
        } _ {
            typ = expr.data:Str
        }

        obj := ""
        ? context.annotationSupport() >< () {
            obj += Visit(context.annotationSupport())
        }
        typ ? I8 {
            typ = "ubyte"
        } I16 {
            typ = "short"
        } I32 {
            typ = "int"
        } I64 {
            typ = "long"
        } U8 {
            typ = "byte"
        } U16 {
            typ = "ushort"
        } U32 {
            typ = "uint"
        } U64 {
            typ = "ulong"
        } F32 {
            typ = "float"
        } F64 {
            typ = "double"
        } Chr {
            typ = "char"
        } Str {
            typ = "string"
        }
        
        obj += ""id.permission" const "typ" "id.text" = "expr.text" "Terminate + Wrap""
        <- (obj)
    }

    VisitNamespaceVariableStatement(context: NamespaceVariableStatementContext) -> (v: {}) {
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

        obj += ""r1.permission" static "typ" "r1.text""
        ? r2 >< () {
            obj += " = "r2.text" "Terminate+Wrap""
        } _ {
            obj += Terminate + Wrap
        }
        <- (obj)
    }

    VisitNamespaceControlStatement(context: NamespaceControlStatementContext) -> (v: {}) {
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
        ? context.packageControlSubStatement().Length > 0 {
            obj += ""r1.permission" static "typ" "r1.text + BlockLeft""
            record := [Str]Bool{}
            context.packageControlSubStatement() @ item {
                temp := Visit(item):Result
                obj += temp.text
                record[temp.data:Str] = True
            }
            ? r2 >< () {
                obj = "protected static "typ" _"r1.text" = "r2.text"; "Wrap"" + obj
                ? ~record.ContainsKey("get") {
                    obj += "get { return _"r1.text"; }"
                }
                ? isMutable & ~record.ContainsKey("set") {
                    obj += "set { _"r1.text" = value; }"
                }
            }
            obj += BlockRight + Wrap
        } _ {
            ? isMutable {
                obj += ""r1.permission" static "typ" "r1.text" { get;set; }"
                ? r2 >< () {
                    obj += " = "r2.text" "Terminate+Wrap""
                } _ {
                    obj += Wrap
                }
            } _ {
                obj += ""r1.permission" static "typ" "r1.text" { get; }"
                ? r2 >< () {
                    obj += " = "r2.text" "Terminate+Wrap""
                } _ {
                    obj += Wrap
                }
            }
        }
        <- (obj)
    }
}
