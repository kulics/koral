\Compiler <- {
    Antlr4\Runtime
    Antlr4\Runtime\Misc
    System
    Library
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

XsVisitor -> {
    ProcessFunctionSupport(items: []FunctionSupportStatementContext) -> (Str) {
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
            [lazy.Count - 1 >= 0 @ i {
                content += BlockRight
            }
        }
        obj += content
        <- (obj)
    }
} ...XsBaseVisitor<{}> {
    VisitFunctionStatement(context: FunctionStatementContext) -> ({}) {
        id := Visit(context.id()):Result
        obj := ""
        # 异步
        ? context.t.Type == FlowRight {
            pout := Visit(context.parameterClauseOut()):Str
            ? pout >< "void" {
                pout = ""Task"<"pout">"
            } else {
                pout = Task
            }
            obj += " async "pout" "id.text""
        } _ {
            obj += ""Visit(context.parameterClauseOut())" "id.text""
        }
        # 泛型
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

    VisitReturnStatement(context: ReturnStatementContext) -> ({}) {
        r := Visit(context.tuple()):Result
        ? r.text == "()" {
            r.text = ""
        }
        <- ("return "r.text" "Terminate" "Wrap"")
    }

    VisitTuple(context: TupleContext) -> ({}) {
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

    VisitTupleExpression(context: TupleExpressionContext) -> ({}) {
        obj := "("
        [0 < context.expression().Length @ i {
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

    VisitParameterClauseIn(context: ParameterClauseInContext) -> ({}) {
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

    VisitParameterClauseOut(context: ParameterClauseOutContext) -> ({}) {
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
            [temp.Count - 1; i >= 0] @ i {
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

    VisitParameter(context: ParameterContext) -> ({}) {
        p := Parameter{}
        id := Visit(context.id()):Result
        p.id = id.text
        p.permission = id.permission
        ? context.annotationSupport() >< () {
            p.annotation = Visit(context.annotationSupport()):Str
        }
        ? context.expression() >< () {
            p.value = "=" (Visit(context.expression()):Result.text ""
        }
        p.type = Visit(context.type()):Str
        <- (p)
    }
}
