"Compiler" {
    "Antlr4/Runtime"
    "Antlr4/Runtime/Misc"
    "System"

    "Compiler" XsParser.
    "Compiler" Compiler Static.
}

keywords := []Str{
    "abstract", "as", "base", "bool", "break" , "byte", "case" , "catch",
    "char","checked","class","const","continue","decimal","default","delegate","do","double","_",
    "enum","event","explicit","extern","false","finally","fixed","float","for","foreach","goto",
    "?","implicit","in","int","interface","internal","is","lock","long","namespace","new","null",
    "object","operator","out","override","params","private","protected","public","readonly","ref",
    "return","sbyte","sealed","short","sizeof","stackalloc","static","string","struct","switch",
    "this","throw","true","try","typeof","uint","ulong","unchecked","unsafe","ushort","using",
    "virtual","void","volatile","while"
}

TemplateItem -> {
    Template(): Str
    Contract(): Str
}

DicEle -> {
    key(): Str
    value(): Str
    text(): Str
}

(me:XsLangVisitor)(base) VisitVariableStatement(context: VariableStatementContext) -> (v: Any) {
    obj := ""
    r1 := Visit(context.expression(0)):(Result)
    r2 := Visit(context.expression(1)):(Result)
    ? context.typeType() >< Nil {
        Type := Visit(context.typeType()):(Str)
        obj = ""Type" "r1.text" = "r2.text"" + Terminate + Wrap
    } _ {
        obj = "var "r1.text" = "r2.text"" + Terminate + Wrap
    }
    <- (obj)
}

(me:XsLangVisitor)(base) VisitVariableDeclaredStatement(context: VariableDeclaredStatementContext) -> (v: Any) {
    obj := ""
    Type := Visit(context.typeType()):(Str)
    r := Visit(context.expression()):(Result)
    obj = ""Type" "r.text"" + Terminate + Wrap
    <- (obj)
}

(me:XsLangVisitor)(base) VisitAssignStatement(context: AssignStatementContext) -> (v: Any) {
    r1 := Visit(context.expression(0)):(Result)
    r2 := Visit(context.expression(1)):(Result)
    obj := r1.text + Visit(context.assign()) + r2.text + Terminate + Wrap
    <- (obj)
}

(me:XsLangVisitor)(base) VisitAssign(context: AssignContext) -> (v: Any) {
    <- (context.op.Text)
}

(me:XsLangVisitor)(base) VisitExpressionStatement(context: ExpressionStatementContext) -> (v: Any) {
    r := Visit(context.expression()):(Result)
    <- (r.text + Terminate + Wrap)
}

(me:XsLangVisitor)(base) VisitExpression(context: ExpressionContext) -> (v: Any) {
    count := context.ChildCount
    r := Result{}
    ? count == 3 {
        e1 := Visit(context.GetChild(0)):(Result)
        e2 := Visit(context.GetChild(2))
        op := Visit(context.GetChild(1))

        context.GetChild(1) ? :JudgeTypeContext {
            r.data = Bool
            e3 := Visit(context.GetChild(2)):(Str)
            op ? "==" {
                r.text = "("e1.text" is "e3")"
            } "><" {
                r.text = "!("e1.text" is "e3")"
            }
            <- (r)
        } :JudgeContext {
            # todo 如果左右不是bool类型值，报错 #
            r.data = Bool
        } :AddContext {
            # todo 如果左右不是number或text类型值，报错 #
            ? e1.data:(Str) == Str | e2:(Result).data:(Str) == Str {
                r.data = Str
            }  e1.data:(Str) == I32 & e2:(Result).data:(Str) == I32 {
                r.data = I32
            } _ {
                r.data = F64
            }
        } :MulContext {
            # todo 如果左右不是number类型值，报错 #
            ? e1.data:(Str) == I32 & e2:(Result).data:(Str) == I32 {
                r.data = I32
            } _ {
                r.data = F64
            }
        } :PowContext {
            # todo 如果左右部署number类型，报错 #
            r.data = F64
            op ? "**" {
                op = "Pow"
            } "//" {
                op = "Root"
            } "%%" {
                op = "Log"
            }
            r.text = ""op"("e1.text", "e2:(Result).text")"
            <- (r)
        }
        r.text = e1.text + op + e2:(Result).text
    } count == 2 {
        r = Visit(context.GetChild(0)):(Result)
        ? context.GetChild(1).GetType() == ?(:TypeConversionContext) {
            e2 := Visit(context.GetChild(1)):(Str)
            r.data = e2
            r.text = "(("e2")("r.text"))"
        } _ {
            ? context.op.Type == XsParser.Bang {
                r.text = "ref "r.text""
            }  context.op.Type == XsParser.Question {
                r.text += "?"
            }
        }
    } count == 1 {
        r = Visit(context.GetChild(0)):(Result)
    }
    <- (r)
}

(me:XsLangVisitor)(base) VisitCallExpression(context: CallExpressionContext) -> (v: Any) {
    count := context.ChildCount
    r := Result{}
    ? count == 3 {
        e1 := Visit(context.GetChild(0)):(Result)
        op := Visit(context.GetChild(1))
        e2 := Visit(context.GetChild(2)):(Result)
        r.text = e1.text + op + e2.text
    } count == 1 {
        r = Visit(context.GetChild(0)):(Result)
    }
    <- (r)
}

(me:XsLangVisitor)(base) VisitTypeConversion(context: TypeConversionContext) -> (v: Any) {
    <- (Visit(context.typeType()):(Str))
}

(me:XsLangVisitor)(base) VisitCall(context: CallContext) -> (v: Any) {
    <- (context.op.Text)
}

(me:XsLangVisitor)(base) VisitWave(context: WaveContext) -> (v: Any) {
    <- (context.op.Text)
}

(me:XsLangVisitor)(base) VisitJudgeType(context: JudgeTypeContext) -> (v: Any) {
    <- (context.op.Text)
}

(me:XsLangVisitor)(base) VisitJudge(context: JudgeContext) -> (v: Any) {
    ? context.op.Text == "><" {
        <- ("!=")
    } context.op.Text == "&" {
        <- ("&&")
    } context.op.Text == "|" {
        <- ("||")
    }
    <- (context.op.Text)
}

(me:XsLangVisitor)(base) VisitAdd(context: AddContext) -> (v: Any) {
    <- (context.op.Text)
}

(me:XsLangVisitor)(base) VisitMul(context: MulContext) -> (v: Any) {
    <- (context.op.Text)
}

(me:XsLangVisitor)(base) VisitPow(context: PowContext) -> (v: Any) {
    <- (context.op.Text)
}

(me:XsLangVisitor)(base) VisitPrimaryExpression(context: PrimaryExpressionContext) -> (v: Any) {
    ? context.ChildCount == 1 {
        c := context.GetChild(0)
        ? c == :DataStatementContext {
            <- (Visit(context.dataStatement()))
        } c == :IdContext {
            <- (Visit(context.id()))
        } context.t.Type == Discard {
            <- (Result{ text = "_", data = "var" })
        }
    } context.ChildCount == 2 {
        id := Visit(context.id()):(Result)
        template := Visit(context.templateCall()):(Str)
        <- (Result{ text = id.text + template, data = id.text + template })
    }
    r := Visit(context.expression()):(Result)
    <- (Result{ text = "(" + r.text + ")", data = r.data })
}

(me:XsLangVisitor)(base) VisitExpressionList(context: ExpressionListContext) -> (v: Any) {
    r := Result{}
    obj := ""
    [0 < context.expression().Length] @ i {
        temp := Visit(context.expression(i)):(Result)
        ? i == 0 {
            obj += temp.text
        } _ {
            obj += ", " + temp.text
        }
    }
    r.text = obj
    r.data = "var"
    <- (r)
}

(me:XsLangVisitor)(base) VisitTemplateDefine(context: TemplateDefineContext) -> (v: Any) {
    item := TemplateItem{}
    item.Template += "<"
    [0 < context.templateDefineItem().Length] @ i {
        ? i > 0 {
            item.Template += ","
            ? item.Contract.len() > 0 {
                item.Contract += ","
            }
        }
        r := Visit(context.templateDefineItem(i)):(TemplateItem)
        item.Template += r.Template
        item.Contract += r.Contract
    }
    item.Template += ">"
    <- (item)
}

(me:XsLangVisitor)(base) VisitTemplateDefineItem(context: TemplateDefineItemContext) -> (v: Any) {
    item := TemplateItem{}
    ? context.id().len() == 1 {
        id1 := context.id(0).GetText()
        item.Template = id1
    } _ {
        id1 := context.id(0).GetText()
        item.Template = id1
        id2 := context.id(1).GetText()
        item.Contract = " where "id1":"id2""
    }
    <- (item)
}

(me:XsLangVisitor)(base) VisitTemplateCall(context: TemplateCallContext) -> (v: Any) {
    obj := ""
    obj += "<"
    [0 < context.typeType().Length] @ i {
        ? i > 0 {
            obj += ","
        }
        r := Visit(context.typeType(i))
        obj += r
    }
    obj += ">"
    <- (obj)
}

(me:XsLangVisitor)(base) VisitCallElement(context: CallElementContext) -> (v: Any) {
    id := Visit(context.id()):(Result)
    ? context.op?.Type == XsParser.Question {
        id.text += "?"
    }
    ? context.expression() == Nil {
        <- (Result{ text = id.text + Visit(context.slice()):(Str) })
    }
    r := Visit(context.expression()):(Result)
    r.text = "" id.text "[" r.text "]"
    <- (r)
}

(me:XsLangVisitor)(base) VisitSlice(context: SliceContext) -> (v: Any) {
    <- (Visit(context.GetChild(0)):(Str))
}

(me:XsLangVisitor)(base) VisitSliceFull(context: SliceFullContext) -> (v: Any) {
    order := ""
    attach := ""
    context.op.Text ? "<=" {
        order = "true"
        attach = "true"
    } "<" {
        order = "true"
    } ">=" {
        order = "false"
        attach = "true"
    } ">" {
        order = "false"
    }
    expr1 := Visit(context.expression(0)):(Result)
    expr2 := Visit(context.expression(1)):(Result)
    <- (".slice("expr1.text", "expr2.text", "order", "attach")")
}

(me:XsLangVisitor)(base) VisitSliceStart(context: SliceStartContext) -> (v: Any) {
    order := ""
    attach := ""
    context.op.Text ? "<=" {
        order = "true"
        attach = "true"
    } "<" {
        order = "true"
    } ">=" {
        order = "false"
        attach = "true"
    } ">" {
        order = "false"
    }
    expr := Visit(context.expression()):(Result)
    <- (".slice("expr.text", null, "order", "attach")")
}

(me:XsLangVisitor)(base) VisitSliceEnd(context: SliceEndContext) -> (v: Any) {
    order := ""
    attach := "false"
    context.op.Text ? "<=" {
        order = "true"
        attach = "true"
    } "<" {
        order = "true"
    } ">=" {
        order = "false"
        attach = "true"
    } ">" {
        order = "false"
    }
    expr := Visit(context.expression()):(Result)
    <- (".slice(null, "expr.text", "order", "attach")")
}

(me:XsLangVisitor)(base) VisitCallFunc(context: CallFuncContext) -> (v: Any) {
    r := Result{data = "var"}
    id := Visit(context.id()):(Result)
    r.text += id.text
    ? context.templateCall() >< Nil {
        r.text += Visit(context.templateCall())
    }
    ? context.tuple() >< Nil {
        r.text += Visit(context.tuple()):(Result).text
    } _ {
        r.text += "(" Visit(context.lambda()):(Result).text ")"
    }

    <- (r)
}

(me:XsLangVisitor)(base) VisitCallPkg(context: CallPkgContext) -> (v: Any) {
    r := Result{data = Visit(context.typeType())}
    r.text = "(new "Visit(context.typeType())"()"
    ? context.pkgAssign() >< Nil {
        r.text += Visit(context.pkgAssign())
    } context.listAssign() >< Nil {
        r.text += Visit(context.listAssign())
    } context.setAssign() >< Nil {
        r.text += Visit(context.setAssign())
    } context.dictionaryAssign() >< Nil {
        r.text += Visit(context.dictionaryAssign())
    }
    r.text += ")"
    <- (r)
}

(me:XsLangVisitor)(base) VisitCallNew(context: CallNewContext) -> (v: Any) {
    r := Result{data = Visit(context.typeType())}
    param := ""
    ? context.expressionList() >< Nil {
        param = Visit(context.expressionList()):(Result).text
    }
    r.text = "(new "Visit(context.typeType())"("param")"
    r.text += ")"
    <- (r)
}

(me:XsLangVisitor)(base) VisitPkgAssign(context: PkgAssignContext) -> (v: Any) {
    obj := ""
    obj += "{"
    [0 < context.pkgAssignElement().Length] @ i {
        ? i == 0 {
            obj += Visit(context.pkgAssignElement(i))
        } _ {
            obj += "," + Visit(context.pkgAssignElement(i))
        }
    }
    obj += "}"
    <- (obj)
}

(me:XsLangVisitor)(base) VisitListAssign(context: ListAssignContext) -> (v: Any) {
    obj := ""
    obj += "{"
    [0 < context.expression().Length] @ i {
        r := Visit(context.expression(i)):(Result)
        ? i == 0 {
            obj += r.text
        } _ {
            obj += "," + r.text
        }
    }
    obj += "}"
    <- (obj)
}

(me:XsLangVisitor)(base) VisitSetAssign(context: SetAssignContext) -> (v: Any) {
    obj := ""
    obj += "{"
    [0 < context.expression().Length] @ i {
        r := Visit(context.expression(i)):(Result)
        ? i == 0 {
            obj += r.text
        } _ {
            obj += "," + r.text
        }
    }
    obj += "}"
    <- (obj)
}

(me:XsLangVisitor)(base) VisitDictionaryAssign(context: DictionaryAssignContext) -> (v: Any) {
    obj := ""
    obj += "{"
    [0 < context.dictionaryElement().Length] @ i {
        r := Visit(context.dictionaryElement(i)):(DicEle)
        ? i == 0 {
            obj += r.text
        } _ {
            obj += "," + r.text
        }
    }
    obj += "}"
    <- (obj)
}

(me:XsLangVisitor)(base) VisitPkgAssignElement(context: PkgAssignElementContext) -> (v: Any) {
    obj := ""
    obj += Visit(context.name()) + " = " + Visit(context.expression()):(Result).text
    <- (obj)
}

(me:XsLangVisitor)(base) VisitPkgAnonymous(context: PkgAnonymousContext) -> (v: Any) {
    <- (Result{
        data = "var",
        text = "new" + Visit(context.pkgAnonymousAssign()):(Str)
    })
}

(me:XsLangVisitor)(base) VisitPkgAnonymousAssign(context: PkgAnonymousAssignContext) -> (v: Any) {
    obj := ""
    obj += "{"
    [0 < context.pkgAnonymousAssignElement().Length] @ i {
        ? i == 0 {
            obj += Visit(context.pkgAnonymousAssignElement(i))
        } _ {
            obj += "," + Visit(context.pkgAnonymousAssignElement(i))
        }
    }
    obj += "}"
    <- (obj)
}

(me:XsLangVisitor)(base) VisitPkgAnonymousAssignElement(context: PkgAnonymousAssignElementContext) -> (v: Any) {
    obj := ""
    obj += Visit(context.name()) + " = " + Visit(context.expression()):(Result).text
    <- (obj)
}

(me:XsLangVisitor)(base) VisitCallAwait(context: CallAwaitContext) -> (v: Any) {
    r := Result{}
    expr := Visit(context.expression()):(Result)
    r.data = "var"
    r.text = "await " + expr.text
    <- (r)
}

(me:XsLangVisitor)(base) VisitList(context: ListContext) -> (v: Any) {
    type := "object"
    result := Result{}
    [0 < context.expression().Length] @ i {
        r := Visit(context.expression(i)):(Result)
        ? i == 0 {
            type = r.data:(Str)
            result.text += r.text
        } _ {
            ? type >< r.data:(Str) {
                type = "object"
            }
            result.text += "," + r.text
        }
    }
    result.data = "Lst<"type">"
    result.text = "(new "result.data"(){ "result.text" })"
    <- (result)
}

(me:XsLangVisitor)(base) VisitSet(context: SetContext) -> (v: Any) {
    type := "object"
    result := Result{}
    [0 < context.expression().Length] @ i {
        r := Visit(context.expression(i)):(Result)
        ? i == 0 {
            type = r.data:(Str)
            result.text += r.text
        } _ {
            ? type >< r.data:(Str) {
                type = "object"
            }
            result.text += "," + r.text
        }
    }
    result.data = "Set<"type">"
    result.text = "(new "result.data"(){ "result.text" })"
    <- (result)
}

(me:XsLangVisitor)(base) VisitDictionary(context: DictionaryContext) -> (v: Any) {
    key := Any
    value := Any
    result := Result{}
    [0 < context.dictionaryElement().Length] @ i {
        r := Visit(context.dictionaryElement(i)):(DicEle)
        ? i == 0 {
            key = r.key
            value = r.value
            result.text += r.text
        } _ {
            ? key >< r.key {
                key = Any
            }
            ? value >< r.value {
                value = Any
            }
            result.text += "," + r.text
        }
    }
    type := key + "," + value
    result.data = "Dic<"type">"
    result.text = "(new "result.data"(){ "result.text" })"
    <- (result)
}

(me:XsLangVisitor)(base) VisitDictionaryElement(context: DictionaryElementContext) -> (v: Any) {
    r1 := Visit(context.expression(0)):(Result)
    r2 := Visit(context.expression(1)):(Result)
    result := DicEle{
        key = r1.data:(Str),
        value = r2.data:(Str),
        text = "{" + r1.text + "," + r2.text + "}"
    }
    <- (result)
}

(me:XsLangVisitor)(base) VisitStringExpression(context: StringExpressionContext) -> (v: Any) {
    text := "(new System.Text.StringBuilder("context.TextLiteral().GetText()")"
    context.stringExpressionElement() @ item {
        text += Visit(item)
    }
    text += ").to_Str()"
    <- (Result{
        data = Str,
        text = text
    })
}

(me:XsLangVisitor)(base) VisitStringExpressionElement(context: StringExpressionElementContext) -> (v: Any) {
    r := Visit(context.expression()):(Result)
    text := context.TextLiteral().GetText()
    <- (".Append("r.text").Append("text")")
}

(me:XsLangVisitor)(base) VisitDataStatement(context: DataStatementContext) -> (v: Any) {
    r := Result{}
    ? context.nilExpr() >< Nil {
        r.data = Any
        r.text = "null"
    } context.floatExpr() >< Nil {
        r.data = F64
        r.text = Visit(context.floatExpr()):(Str)
    } context.integerExpr() >< Nil {
        r.data = I32
        r.text = Visit(context.integerExpr()):(Str)
    } context.t.Type == TextLiteral {
        r.data = Str
        r.text = context.TextLiteral().GetText()
    } context.t.Type == XsParser.CharLiteral {
        r.data = Chr
        r.text = context.CharLiteral().GetText()
    } context.t.Type == XsParser.TrueLiteral {
        r.data = Bool
        r.text = T
    } context.t.Type == XsParser.FalseLiteral {
        r.data = Bool
        r.text = F
    }
    <- (r)
}

(me:XsLangVisitor)(base) VisitFloatExpr(context: FloatExprContext) -> (v: Any) {
    number := ""
    number += Visit(context.integerExpr(0)) + "." + Visit(context.integerExpr(1))
    <- (number)
}

(me:XsLangVisitor)(base) VisitIntegerExpr(context: IntegerExprContext) -> (v: Any) {
    number := ""
    context.NumberLiteral() @ item {
        number += item.GetText()
    }
    <- (number)
}

(me:XsLangVisitor)(base) VisitFunctionExpression(context: FunctionExpressionContext) -> (v: Any) {
    r := Result{}
    # 异步 #
    ? context.t.Type == Right_Flow {
        r.text += " async "
    }
    r.text += Visit(context.parameterClauseIn()) + " => " + BlockLeft + Wrap
    r.text += ProcessFunctionSupport(context.functionSupportStatement())
    r.text += BlockRight + Wrap
    r.data = "var"
    <- (r)
}

(me:XsLangVisitor)(base) VisitLambda(context: LambdaContext) -> (v: Any) {
    r := Result{data = "var"}
    # 异步 #
    ? context.t.Type == Right_Flow {
        r.text += "async "
    }
    r.text += "("
    ? context.lambdaIn() >< Nil {
        r.text += Visit(context.lambdaIn())
    }
    r.text += ")"
    r.text += "=>"

    ? context.expressionList() >< Nil {
        r.text += Visit(context.expressionList()):(Result).text
    } _ {
        r.text += "{" + ProcessFunctionSupport(context.functionSupportStatement()) + "}"
    }

    <- (r)
}

(me:XsLangVisitor)(base) VisitLambdaIn(context: LambdaInContext) -> (v: Any) {
    obj := ""
    [0 < context.id().Length] @ i {
        r := Visit(context.id(i)):(Result)
        ? i == 0 {
            obj += r.text
        } _ {
            obj += ", " + r.text
        }
    }
    <- (obj)
}

(me:XsLangVisitor)(base) VisitPlusMinus(context: PlusMinusContext) -> (v: Any) {
    r := Result{}
    expr := Visit(context.expression()):(Result)
    op := Visit(context.add())
    r.data = expr.data
    r.text = op + expr.text
    <- (r)
}

(me:XsLangVisitor)(base) VisitNegate(context: NegateContext) -> (v: Any) {
    r := Result{}
    expr := Visit(context.expression()):(Result)
    r.data = expr.data
    r.text = "!" + expr.text
    <- (r)
}
