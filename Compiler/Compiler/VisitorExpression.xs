\Compiler <- {
    Antlr4\Runtime
    Antlr4\Runtime\Misc
    System

    Compiler.XsParser
    Compiler.Compiler Static
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

XsLangVisitor -> {
} ...XsParserBaseVisitor<{}> {
    VisitVariableStatement(context: VariableStatementContext) -> (v:{}) {
        obj := ""
        r1 := Visit(context.expression(0)):Result
        r2 := Visit(context.expression(1)):Result
        ? context.typeType() >< () {
            Type := Visit(context.typeType()):Str
            obj = ""Type" "r1.text" = "r2.text"" + Terminate + Wrap
        } _ {
            obj = "var "r1.text" = "r2.text"" + Terminate + Wrap
        }
        <- (obj)
    }

    VisitVariableDeclaredStatement(context: VariableDeclaredStatementContext) -> (v:{}) {
        obj := ""
        Type := Visit(context.typeType()):Str
        r := Visit(context.expression()):Result
        obj = ""Type" "r.text"" + Terminate + Wrap
        <- (obj)
    }

    VisitAssignStatement(context: AssignStatementContext) -> (v:{}) {
        r1 := Visit(context.expression(0)):Result
        r2 := Visit(context.expression(1)):Result
        obj := r1.text + Visit(context.assign()) + r2.text + Terminate + Wrap
        <- (obj)
    }

    VisitAssign(context: AssignContext) -> (v:{}) {
        <- (context.op.Text)
    }

    VisitExpressionStatement(context: ExpressionStatementContext) -> (v:{}) {
        r := Visit(context.expression()):Result
        <- (r.text + Terminate + Wrap)
    }

    VisitExpression(context: ExpressionContext) -> (v:{}) {
        count := context.ChildCount
        r := Result{}
        ? count == 3 {
            e1 := Visit(context.GetChild(0)):Result
            e2 := Visit(context.GetChild(2))
            op := Visit(context.GetChild(1))

            context.GetChild(1) ? :JudgeTypeContext {
                r.data = Bool
                e3 := Visit(context.GetChild(2)):Str
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
                ? e1.data:Str == Str | e2:Result.data:Str == Str {
                    r.data = Str
                }  e1.data:Str == I32 & e2:Result.data:Str == I32 {
                    r.data = I32
                } _ {
                    r.data = F64
                }
            } :MulContext {
                # todo 如果左右不是number类型值，报错 #
                ? e1.data:Str == I32 & e2:Result.data:Str == I32 {
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
                r.text = ""op"("e1.text", "e2:Result.text")"
                <- (r)
            }
            r.text = e1.text + op + e2:Result.text
        } count == 2 {
            r = Visit(context.GetChild(0)):Result
            ? context.GetChild(1).GetType() == ?(:TypeConversionContext) {
                e2 := Visit(context.GetChild(1)):Str
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
            r = Visit(context.GetChild(0)):Result
        }
        <- (r)
    }

    VisitCallBase(context: CallBaseContext) -> (v:{}) {
        r := Result{data = "var"}
        e1 := "base"
        op := "."
        e2 := Visit(context.GetChild(1)):Result
        r.text = e1 + op + e2.text
        <- (r)
    }

    VisitCallSelf(context: CallSelfContext) -> (v:{}) {
        r := Result{data = "var"}
        e1 := "this"
        op := "."
        e2 := Visit(context.GetChild(1)):Result
        r.text = e1 + op + e2.text
        <- (r)
    }

    VisitCallNameSpace(context: CallNameSpaceContext) -> (v:{}) {
        obj := ""
        [0 < context.id().Length] @ i {
            id := Visit(context.id(i)):Result
            ? i == 0 {
                obj += "" + id.text
            } _ {
                obj += "." + id.text
            }
        }

        r := Result{data = "var"}
        e1 := obj
        op := "."
        e2 := Visit(context.callExpression()):Result
        r.text = e1 + op + e2.text
        <- (r)
    }

    VisitCallExpression(context: CallExpressionContext) -> (v:{}) {
        count := context.ChildCount
        r := Result{}
        ? count == 3 {
            e1 := Visit(context.GetChild(0)):Result
            op := Visit(context.GetChild(1))
            e2 := Visit(context.GetChild(2)):Result
            r.text = e1.text + op + e2.text
        } count == 1 {
            r = Visit(context.GetChild(0)):Result
        }
        <- (r)
    }

    VisitTypeConversion(context: TypeConversionContext) -> (v:{}) {
        <- (Visit(context.typeType()):Str)
    }

    VisitCall(context: CallContext) -> (v:{}) {
        <- (context.op.Text)
    }

    VisitWave(context: WaveContext) -> (v:{}) {
        <- (context.op.Text)
    }

    VisitJudgeType(context: JudgeTypeContext) -> (v:{}) {
        <- (context.op.Text)
    }

    VisitJudge(context: JudgeContext) -> (v:{}) {
        ? context.op.Text == "><" {
            <- ("!=")
        } context.op.Text == "&" {
            <- ("&&")
        } context.op.Text == "|" {
            <- ("||")
        }
        <- (context.op.Text)
    }

    VisitAdd(context: AddContext) -> (v:{}) {
        <- (context.op.Text)
    }

    VisitMul(context: MulContext) -> (v:{}) {
        <- (context.op.Text)
    }

    VisitPow(context: PowContext) -> (v:{}) {
        <- (context.op.Text)
    }

    VisitPrimaryExpression(context: PrimaryExpressionContext) -> (v:{}) {
        ? context.ChildCount == 1 {
            c := context.GetChild(0)
            ? c == :DataStatementContext {
                <- (Visit(context.dataStatement()))
            }  (c == :IdContext) {
                <- (Visit(context.id()))
            }  (context.t.Type == Dot_Dot) {
                <- (Result{ text = "this", data = "var" })
            }  (context.t.Type == Discard) {
                <- (Result{ text = "_", data = "var" })
            }
        } context.ChildCount == 2 {
            id := Visit(context.id()):Result
            template := Visit(context.templateCall()):Str
            <- (Result{ text = id.text + template, data = id.text + template })
        }
        r := Visit(context.expression()):Result
        <- (Result{ text = "(" + r.text + ")", data = r.data })
    }

    VisitExpressionList(context: ExpressionListContext) -> (v:{}) {
        r := Result{}
        obj := ""
        [0 < context.expression().Length] @ i {
            temp := Visit(context.expression(i)):Result
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

    VisitTemplateDefine(context: TemplateDefineContext) -> (v:{}) {
        item := TemplateItem{}
        item.Template += "<"
        [0 < context.templateDefineItem().Length] @ i {
            ? i > 0 {
                item.Template += ","
                ? item.Contract.len() > 0 {
                    item.Contract += ","
                }
            }
            r := Visit(context.templateDefineItem(i)):TemplateItem
            item.Template += r.Template
            item.Contract += r.Contract
        }
        item.Template += ">"
        <- (item)
    }

    VisitTemplateDefineItem(context: TemplateDefineItemContext) -> (v:{}) {
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

    VisitTemplateCall(context: TemplateCallContext) -> (v:{}) {
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

    VisitCallElement(context: CallElementContext) -> (v:{}) {
        id := Visit(context.id()):Result
        ? context.op?.Type == XsParser.Question {
            id.text += "?"
        }
        ? context.expression() == () {
            <- (Result{ text = id.text + Visit(context.slice()):Str })
        }
        r := Visit(context.expression()):Result
        r.text = "" id.text "[" r.text "]"
        <- (r)
    }

    VisitSlice(context: SliceContext) -> (v:{}) {
        <- (Visit(context.GetChild(0)):Str)
    }

    VisitSliceFull(context: SliceFullContext) -> (v:{}) {
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
        expr1 := Visit(context.expression(0)):Result
        expr2 := Visit(context.expression(1)):Result
        <- (".slice("expr1.text", "expr2.text", "order", "attach")")
    }

    VisitSliceStart(context: SliceStartContext) -> (v:{}) {
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
        expr := Visit(context.expression()):Result
        <- (".slice("expr.text", null, "order", "attach")")
    }

    VisitSliceEnd(context: SliceEndContext) -> (v:{}) {
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
        expr := Visit(context.expression()):Result
        <- (".slice(null, "expr.text", "order", "attach")")
    }

    VisitCallFunc(context: CallFuncContext) -> (v:{}) {
        r := Result{data = "var"}
        id := Visit(context.id()):Result
        r.text += id.text
        ? context.templateCall() >< () {
            r.text += Visit(context.templateCall())
        }
        ? context.tuple() >< () {
            r.text += Visit(context.tuple()):Result.text
        } _ {
            r.text += "(" Visit(context.lambda()):Result.text ")"
        }

        <- (r)
    }

    VisitCallPkg(context: CallPkgContext) -> (v:{}) {
        r := Result{data = Visit(context.typeType())}
        r.text = "(new "Visit(context.typeType())"()"
        ? context.pkgAssign() >< () {
            r.text += Visit(context.pkgAssign())
        } context.listAssign() >< () {
            r.text += Visit(context.listAssign())
        } context.setAssign() >< () {
            r.text += Visit(context.setAssign())
        } context.dictionaryAssign() >< () {
            r.text += Visit(context.dictionaryAssign())
        }
        r.text += ")"
        <- (r)
    }

    VisitCallNew(context: CallNewContext) -> (v:{}) {
        r := Result{data = Visit(context.typeType())}
        param := ""
        ? context.expressionList() >< () {
            param = Visit(context.expressionList()):Result.text
        }
        r.text = "(new "Visit(context.typeType())"("param")"
        r.text += ")"
        <- (r)
    }

    VisitPkgAssign(context: PkgAssignContext) -> (v:{}) {
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

    VisitListAssign(context: ListAssignContext) -> (v:{}) {
        obj := ""
        obj += "{"
        [0 < context.expression().Length] @ i {
            r := Visit(context.expression(i)):Result
            ? i == 0 {
                obj += r.text
            } _ {
                obj += "," + r.text
            }
        }
        obj += "}"
        <- (obj)
    }

    VisitSetAssign(context: SetAssignContext) -> (v:{}) {
        obj := ""
        obj += "{"
        [0 < context.expression().Length] @ i {
            r := Visit(context.expression(i)):Result
            ? i == 0 {
                obj += r.text
            } _ {
                obj += "," + r.text
            }
        }
        obj += "}"
        <- (obj)
    }

    VisitDictionaryAssign(context: DictionaryAssignContext) -> (v:{}) {
        obj := ""
        obj += "{"
        [0 < context.dictionaryElement().Length] @ i {
            r := Visit(context.dictionaryElement(i)):DicEle
            ? i == 0 {
                obj += r.text
            } _ {
                obj += "," + r.text
            }
        }
        obj += "}"
        <- (obj)
    }

    VisitPkgAssignElement(context: PkgAssignElementContext) -> (v:{}) {
        obj := ""
        obj += Visit(context.name()) + " = " + Visit(context.expression()):Result.text
        <- (obj)
    }

    VisitPkgAnonymous(context: PkgAnonymousContext) -> (v:{}) {
        <- (Result{
            data = "var",
            text = "new" + Visit(context.pkgAnonymousAssign()):Str
        })
    }

    VisitPkgAnonymousAssign(context: PkgAnonymousAssignContext) -> (v:{}) {
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

    VisitPkgAnonymousAssignElement(context: PkgAnonymousAssignElementContext) -> (v:{}) {
        obj := ""
        obj += Visit(context.name()) + " = " + Visit(context.expression()):Result.text
        <- (obj)
    }

    VisitCallAwait(context: CallAwaitContext) -> (v:{}) {
        r := Result{}
        expr := Visit(context.expression()):Result
        r.data = "var"
        r.text = "await " + expr.text
        <- (r)
    }

    VisitList(context: ListContext) -> (v:{}) {
        type := "object"
        result := Result{}
        [0 < context.expression().Length] @ i {
            r := Visit(context.expression(i)):Result
            ? i == 0 {
                type = r.data:Str
                result.text += r.text
            } _ {
                ? type >< r.data:Str {
                    type = "object"
                }
                result.text += "," + r.text
            }
        }
        result.data = "Lst<"type">"
        result.text = "(new "result.data"(){ "result.text" })"
        <- (result)
    }

    VisitSet(context: SetContext) -> (v:{}) {
        type := "object"
        result := Result{}
        [0 < context.expression().Length] @ i {
            r := Visit(context.expression(i)):Result
            ? i == 0 {
                type = r.data:Str
                result.text += r.text
            } _ {
                ? type >< r.data:Str {
                    type = "object"
                }
                result.text += "," + r.text
            }
        }
        result.data = "Set<"type">"
        result.text = "(new "result.data"(){ "result.text" })"
        <- (result)
    }

    VisitDictionary(context: DictionaryContext) -> (v:{}) {
        key := Any
        value := Any
        result := Result{}
        [0 < context.dictionaryElement().Length] @ i {
            r := Visit(context.dictionaryElement(i)):DicEle
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

    VisitDictionaryElement(context: DictionaryElementContext) -> (v:{}) {
        r1 := Visit(context.expression(0)):Result
        r2 := Visit(context.expression(1)):Result
        result := DicEle{
            key = r1.data:Str,
            value = r2.data:Str,
            text = "{" + r1.text + "," + r2.text + "}"
        }
        <- (result)
    }

    VisitStringExpression(context: StringExpressionContext) -> (v:{}) {
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

    VisitStringExpressionElement(context: StringExpressionElementContext) -> (v:{}) {
        r := Visit(context.expression()):Result
        text := context.TextLiteral().GetText()
        <- (".Append("r.text").Append("text")")
    }

    VisitDataStatement(context: DataStatementContext) -> (v:{}) {
        r := Result{}
        ? context.nilExpr() >< () {
            r.data = Any
            r.text = "null"
        } context.floatExpr() >< () {
            r.data = F64
            r.text = Visit(context.floatExpr()):Str
        } context.integerExpr() >< () {
            r.data = I32
            r.text = Visit(context.integerExpr()):Str
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

    VisitFloatExpr(context: FloatExprContext) -> (v:{}) {
        number := ""
        number += Visit(context.integerExpr(0)) + "." + Visit(context.integerExpr(1))
        <- (number)
    }

    VisitIntegerExpr(context: IntegerExprContext) -> (v:{}) {
        number := ""
        context.NumberLiteral() @ item {
            number += item.GetText()
        }
        <- (number)
    }

    VisitFunctionExpression(context: FunctionExpressionContext) -> (v:{}) {
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

    VisitLambda(context: LambdaContext) -> (v:{}) {
        r := Result{data = "var"}
        # 异步 #
        ? context.t.Type == Right_Flow {
            r.text += "async "
        }
        r.text += "("
        ? context.lambdaIn() >< () {
            r.text += Visit(context.lambdaIn())
        }
        r.text += ")"
        r.text += "=>"

        ? context.expressionList() >< () {
            r.text += Visit(context.expressionList()):Result.text
        } _ {
            r.text += "{" + ProcessFunctionSupport(context.functionSupportStatement()) + "}"
        }

        <- (r)
    }

    VisitLambdaIn(context: LambdaInContext) -> (v:{}) {
        obj := ""
        [0 < context.id().Length] @ i {
            r := Visit(context.id(i)):Result
            ? i == 0 {
                obj += r.text
            } _ {
                obj += ", " + r.text
            }
        }
        <- (obj)
    }

    VisitPlusMinus(context: PlusMinusContext) -> (v:{}) {
        r := Result{}
        expr := Visit(context.expression()):Result
        op := Visit(context.add())
        r.data = expr.data
        r.text = op + expr.text
        <- (r)
    }

    VisitNegate(context: NegateContext) -> (v:{}) {
        r := Result{}
        expr := Visit(context.expression()):Result
        r.data = expr.data
        r.text = "!" + expr.text
        <- (r)
    }
}
