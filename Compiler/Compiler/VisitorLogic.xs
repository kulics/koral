\Compiler <- {
    Antlr4\Runtime
    Antlr4\Runtime\Misc
    System
    Library
    Compiler.XsParser
    Compiler.Compiler Static
}

Iterator -> {
    begin(): Result
    end(): Result
    step(): Result
    order() := T
    attach() := F
}

XsVisitor -> {
} ...XsBaseVisitor<{}> {
    VisitIteratorStatement(context: IteratorStatementContext) -> ({}) {
        it := Iterator{}
        ? context.op.Text == ">=" | context.op.Text == "<=" {
            it.attach = T
        }
        ? context.op.Text == ">" | context.op.Text == ">=" {
            it.order = F
        }
        ? context.expression().Length == 2 {
            it.begin = Visit(context.expression(0)):Result
            it.end = Visit(context.expression(1)):Result
            it.step = Result{ data = I32, text = "1" }
        } _ {
            it.begin = Visit(context.expression(0)):Result
            it.end = Visit(context.expression(1)):Result
            it.step = Visit(context.expression(2)):Result
        }
        <- (it)
    }

    VisitLoopStatement(context: LoopStatementContext) -> ({}) {
        obj := ""
        id := "ea"
        ? context.id() >< () {
            id = Visit(context.id()):Result.text
        }
        it := Visit(context.iteratorStatement()):Iterator

        obj += "foreach (var "id" in Range("it.begin.text","it.end.text","it.step.text","it.order","it.attach"))"

        obj += ""Wrap" "BlockLeft" "Wrap""
        obj += ProcessFunctionSupport(context.functionSupportStatement())
        obj += ""BlockRight" "Terminate" "Wrap""
        <- (obj)
    }

    VisitLoopInfiniteStatement(context: LoopInfiniteStatementContext) -> ({}) {
        obj := "for (;;) "Wrap" "BlockLeft" "Wrap""
        obj += ProcessFunctionSupport(context.functionSupportStatement())
        obj += ""BlockRight" "Terminate" "Wrap""
        <- (obj)
    }

    VisitLoopEachStatement(context: LoopEachStatementContext) -> ({}) {
        obj := ""
        arr := Visit(context.expression()):Result
        target := arr.text
        id := "ea"
        ? context.id().Length == 2 {
            target = "Range("target")"
            id = "("Visit(context.id(0)):Result.text","Visit(context.id(1)):Result.text")"
        } context.id().Length == 1 {
            id = Visit(context.id(0)):Result.text
        }

        obj += "foreach (var "id" in "target")"
        obj += ""Wrap" "BlockLeft" "Wrap""
        obj += ProcessFunctionSupport(context.functionSupportStatement())
        obj += ""BlockRight" "Terminate" "Wrap""
        <- (obj)
    }

    VisitLoopCaseStatement(context: LoopCaseStatementContext) -> ({}) {
        obj := ""
        expr := Visit(context.expression()):Result
        obj += "for ( ;"expr.text" ;)"
        obj += ""Wrap" "BlockLeft" "Wrap""
        obj += ProcessFunctionSupport(context.functionSupportStatement())
        obj += ""BlockRight" "Terminate" "Wrap""
        <- (obj)
    }

    VisitLoopJumpStatement(context: LoopJumpStatementContext) -> ({}) {
        <- ("break "Terminate" "Wrap"")
    }

    VisitLoopContinueStatement(context: LoopContinueStatementContext) -> ({}) {
        <- ("continue "Terminate" "Wrap"")
    }

    VisitJudgeCaseStatement(context: JudgeCaseStatementContext) -> ({})  {
        obj := ""
        expr := Visit(context.expression()):Result
        obj += "switch ("expr.text") "Wrap" "BlockLeft" "Wrap""
        foreach (var item in context.caseStatement()) {
            var r = (string)Visit(item);
            obj += r + Wrap;
        }
        obj += ""BlockRight" "Wrap""
        <- (obj)
    }

    VisitCaseDefaultStatement(context: CaseDefaultStatementContext) -> ({}) {
        obj := ""
        obj += "default:"BlockLeft" "Wrap""
        obj += ProcessFunctionSupport(context.functionSupportStatement())
        obj += ""BlockRight"break;"
        <- (obj)
    }

    VisitCaseExprStatement(context: CaseExprStatementContext) -> ({}) {
        obj := ""
        ? context.type() == () {
            expr := Visit(context.expression()):Result
            obj += "case "expr.text" :"Wrap""
        } _ {
            id := "it"
            ? context.id() >< () {
                id = Visit(context.id()):Result.text
            }
            type := Visit(context.type()):Str
            obj += "case "type" "id" :"Wrap""
        }

        obj += ""BlockLeft" "ProcessFunctionSupport(context.functionSupportStatement())"" BlockRight" "
        obj += "break;"
        <- (obj)
    }

    VisitCaseStatement(context: CaseStatementContext) -> ({}) {
        obj := Visit(context.GetChild(0)):Str
        <- (obj)
    }

    VisitJudgeStatement(context: JudgeStatementContext) -> ({}) {
        obj := ""
        obj += Visit(context.judgeIfStatement())
        context.judgeElseIfStatement() @ it {
            obj += Visit(it)
        }
        ? context.judgeElseStatement() >< () {
            obj += Visit(context.judgeElseStatement())
        }
        <- (obj)
    }

    VisitJudgeIfStatement(context: JudgeIfStatementContext) -> ({}) {
        b := Visit(context.expression()):Result
        obj := "if ( "b.text" ) "Wrap" "BlockLeft" "Wrap""
        obj += ProcessFunctionSupport(context.functionSupportStatement())
        obj += ""BlockRight""Wrap""
        <- (obj)
    }

    VisitJudgeElseIfStatement(context: JudgeElseIfStatementContext) -> ({}) {
        b := Visit(context.expression()):Result
        obj := "else if ( "b.text" ) "Wrap" "BlockLeft" "Wrap""
        obj += ProcessFunctionSupport(context.functionSupportStatement())
        obj += ""BlockRight" "Wrap""
        <- (obj)
    }

    VisitJudgeElseStatement(context: JudgeElseStatementContext) -> ({}) {
        obj := "else "Wrap" "BlockLeft" "Wrap""
        obj += ProcessFunctionSupport(context.functionSupportStatement())
        obj += ""BlockRight""Wrap""
        <- (obj)
    }

    VisitCheckStatement(context: CheckStatementContext) -> ({}) {
        obj := "try "BlockLeft" "Wrap""
        obj += ProcessFunctionSupport(context.functionSupportStatement())
        obj += ""BlockRight""Wrap""
        context.checkErrorStatement() @ item {
            obj += ""Visit(item)"" Wrap""
        }

        ? context.checkFinallyStatment() >< () {
            obj += Visit(context.checkFinallyStatment())
        }
        <- (obj)
    }

    VisitCheckErrorStatement(context: CheckErrorStatementContext) -> ({}) {
        obj := ""
        ID := "ex"
        ? context.id() >< () {
            ID = Visit(context.id()):Result.text
        }

        Type := "Exception"
        ? context.type() >< () {
            Type = (string)Visit(context.type())
        }

        obj += "catch( "Type" "ID" )"Wrap""BlockLeft""Wrap" "
        obj += ProcessFunctionSupport(context.functionSupportStatement())
        obj += BlockRight
        <- (obj)
    }

    VisitCheckFinallyStatment(context: CheckFinallyStatmentContext) -> ({}) {
        obj := "finally "Wrap" "BlockLeft""Wrap""
        obj += ProcessFunctionSupport(context.functionSupportStatement())
        obj += ""BlockRight""Wrap""
        <- (obj)
    }

    VisitUsingStatement(context: UsingStatementContext) -> ({}) {
        obj := ""
        r2 := Visit(context.expression(0)):Result
        r1 := Visit(context.expression(1)):Result
        ? context.type() >< () {
            Type := Visit(context.type()):Str
            obj = ""Type" "r1.text" = "r2.text""
        } else {
            obj = "var "r1.text" = "r2.text""
        }
        <- (obj)
    }

    VisitReportStatement(context: ReportStatementContext) -> ({}) {
        obj := ""
        ? context.expression() >< () {
            r := Visit(context.expression()):Result
            obj += r.text
        }
        <- ("throw "obj""Terminate""Wrap"")
    }

    VisitLinq(context: LinqContext) -> ({}) {
        r := Result{data = "var"}
        r.text += "from " Visit(context.expression(0))):Result.text " "
        context.linqItem() @ item {
            r.text += "" Visit(item) " "
        }
        r.text += ""context.k.Text " " Visit(context.expression(1)):Result.text
        <- (r)
    }

    VisitLinqItem(context: LinqItemContext) -> ({}) {
        obj := Visit(context.linqBodyKeyword()):Str
        ? context.expression() >< () {
            obj += " "Visit(context.expression()):Result.text""
        }
        <- (obj)
    }

    VisitLinqKeyword(context: LinqKeywordContext) -> ({}) {
        <- (Visit(context.GetChild(0)))
    }

    VisitLinqHeadKeyword(context: LinqHeadKeywordContext) -> ({}) {
        <- (context.k.Text)
    }

    VisitLinqBodyKeyword(context: LinqBodyKeywordContext) -> ({}) {
        <- (context.k.Text)
    }
}
