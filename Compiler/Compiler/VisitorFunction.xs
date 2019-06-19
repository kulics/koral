\Compiler <- {
    Antlr4\Runtime
    Antlr4\Runtime\Misc
    System

    Compiler.XsParser
    Compiler.Compiler Static
}

Parameter -> {
    id(): Str
    type(): Str
    value(): Str
    annotation(): Str
    permission(): Str
}

XsLangVisitor -> {
    ProcessFunctionSupport(items: [:]FunctionSupportStatementContext) -> (v:Str) {
        obj := ""
        content := ""
        lazy := []Str{}
        items @ item {
            ? item.GetChild(0) == :UsingStatementContext {
                lazy.add("}")
                content += "using ("Visit(item):Str") "BlockLeft" "Wrap""
            } _ {
                content += Visit(item)
            }
        }
        ? lazy.Count > 0 {
            [lazy.Count - 1 >= 0] @ i {
                content += BlockRight
            }
        }
        obj += content
        <- (obj)
    }
} ...XsParserBaseVisitor<{}> {
    VisitFunctionStatement(context: FunctionStatementContext) -> (v: {}) {
        id := Visit(context.id()):Result
        obj := ""
        # 异步 #
        ? context.t.Type == Right Flow {
            pout := Visit(context.parameterClauseOut()):Str
            ? pout >< "void" {
                pout = ""Task"<"pout">"
            } _ {
                pout = Task
            }
            obj += " async "pout" "id.text""
        } _ {
            obj += ""Visit(context.parameterClauseOut())" "id.text""
        }
        # 泛型 #
        templateContract := ""
        ? context.templateDefine() >< () {
            template := Visit(context.templateDefine()):TemplateItem
            obj += template.Template
            templateContract = template.Contract
        }
        obj += ""Visit(context.parameterClauseIn())" "templateContract" "Wrap" "BlockLeft" "Wrap""
        obj += ProcessFunctionSupport(context.functionSupportStatement())
        obj += BlockRight + Wrap
        <- (obj)
    }

    VisitReturnStatement(context: ReturnStatementContext) -> (v: {}) {
        r := Visit(context.tuple()):Result
        ? r.text == "()" {
            r.text = ""
        }
        <- ("return "r.text" "Terminate" "Wrap"")
    }

    VisitTuple(context: TupleContext) -> (v: {}) {
        obj := "("
        [0 < context.expression().Length] @ i {
            r := Visit(context.expression(i)):Result
            ? i == 0 {
                obj += r.text
            } _ {
                obj += ", " r.text ""
            }
        }
        obj += ")"
        result := Result{ data = "var", text = obj }
        <- (result)
    }

    VisitTupleExpression(context: TupleExpressionContext) -> (v: {}) {
        obj := "("
        [0 < context.expression().Length] @ i {
            r := Visit(context.expression(i)):Result
            ? i == 0 {
                obj += r.text;
            } _ {
                obj += ", " r.text ""
            }
        }
        obj += ")"
        result := Result{ data = "var", text = obj }
        <- (result)
    }

    VisitParameterClauseIn(context: ParameterClauseInContext) -> (v: {}) {
        obj := "("
        temp := []Str{}
        [context.parameter().Length - 1 >= 0] @ i {
            p := Visit(context.parameter(i)):Parameter
            temp.add(""p.annotation" "p.type" "p.id" "p.value"")
        }
        [temp.Count - 1 >= 0] @ i {
            ? i == temp.Count - 1 {
                obj += temp[i]
            } _ {
                obj += ", "temp[i]""
            }
        }

        obj += ")"
        <- (obj)
    }

    VisitParameterClauseOut(context: ParameterClauseOutContext) -> (v: {}) {
        obj := ""
        ? context.parameter().Length == 0 {
            obj += "void"
        } context.parameter().Length == 1 {
            p := Visit(context.parameter(0)):Parameter
            obj += p.type
        }
        ? context.parameter().Length > 1 {
            obj += "( "
            temp := []Str{}
            [context.parameter().Length - 1 >= 0] @ i {
                p := Visit(context.parameter(i)):Parameter
                temp.add(""p.annotation" "p.type" "p.id" "p.value"")
            }
            [temp.Count - 1 >= 0] @ i {
                ? i == temp.Count - 1 {
                    obj += temp[i]
                } _ {
                    obj += ", "temp[i]""
                }
            }
            obj += " )"
        }
        <- (obj)
    }

    VisitParameterClauseSelf(context: ParameterClauseSelfContext) -> (v: {}) {
        p := Parameter{}
        id := Visit(context.id()):Result
        p.id = id.text
        p.permission = id.permission
        p.type = Visit(context.typeType()):Str
        <- (p)
    }

    VisitParameter(context: ParameterContext) -> (v: {}) {
        p := Parameter{}
        id := Visit(context.id()):Result
        p.id = id.text
        p.permission = id.permission
        ? context.annotationSupport() >< () {
            p.annotation = Visit(context.annotationSupport()):Str
        }
        ? context.expression() >< () {
            p.value = "=" Visit(context.expression()):Result.text ""
        }
        p.type = Visit(context.typeType()):Str
        <- (p)
    }
}
