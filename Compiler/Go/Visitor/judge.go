package visitor

import (
	"xs/parser"

	"github.com/antlr/antlr4/runtime/Go/antlr"
)

func (sf *XsVisitor) VisitJudgeCaseStatement(ctx *parser.JudgeCaseStatementContext) interface{} {
	obj := ""
	expr := sf.Visit(ctx.Expression()).(Result)
	obj += "switch " + expr.Text + BlockLeft + Wrap
	for _, item := range ctx.AllCaseStatement() {
		r := sf.Visit(item).(string)
		obj += r + Wrap
	}
	obj += BlockRight + Wrap
	return obj
}

func (sf *XsVisitor) VisitCaseDefaultStatement(ctx *parser.CaseDefaultStatementContext) interface{} {
	obj := ""
	obj += "default:" + BlockLeft + Wrap
	obj += sf.ProcessFunctionSupport(ctx.AllFunctionSupportStatement())
	obj += BlockRight
	return obj
}

func (sf *XsVisitor) VisitCaseExprStatement(ctx *parser.CaseExprStatementContext) interface{} {
	obj := ""
	if ctx.TypeType() == nil {
		expr := sf.Visit(ctx.Expression()).(Result)
		obj += "case " + expr.Text + " :" + Wrap
	} else {
		// id := "it"
		// ? ctx.id() >< () {
		// 	id = Visit(ctx.id()).(Result).text
		// }
		// type := Visit(ctx.typeType()):Str
		// obj += "case "type" "id" :"Wrap""
	}

	obj += BlockLeft + sf.ProcessFunctionSupport(ctx.AllFunctionSupportStatement()) + BlockRight
	return obj
}

func (sf *XsVisitor) VisitCaseStatement(ctx *parser.CaseStatementContext) interface{} {
	obj := sf.Visit(ctx.GetChild(0).(antlr.ParseTree)).(string)
	return obj
}

func (sf *XsVisitor) VisitJudgeStatement(ctx *parser.JudgeStatementContext) interface{} {
	obj := ""
	obj += sf.Visit(ctx.JudgeIfStatement()).(string)
	for _, it := range ctx.AllJudgeElseIfStatement() {
		obj += sf.Visit(it).(string)
	}
	if ctx.JudgeElseStatement() != nil {
		obj += sf.Visit(ctx.JudgeElseStatement()).(string)
	}
	obj += Wrap
	return obj
}

func (sf *XsVisitor) VisitJudgeIfStatement(ctx *parser.JudgeIfStatementContext) interface{} {
	b := sf.Visit(ctx.Expression()).(Result)
	obj := "if " + b.Text + BlockLeft + Wrap
	obj += sf.ProcessFunctionSupport(ctx.AllFunctionSupportStatement())
	obj += BlockRight
	return obj
}

func (sf *XsVisitor) VisitJudgeElseIfStatement(ctx *parser.JudgeElseIfStatementContext) interface{} {
	b := sf.Visit(ctx.Expression()).(Result)
	obj := "else if " + b.Text + BlockLeft + Wrap
	obj += sf.ProcessFunctionSupport(ctx.AllFunctionSupportStatement())
	obj += BlockRight
	return obj
}

func (sf *XsVisitor) VisitJudgeElseStatement(ctx *parser.JudgeElseStatementContext) interface{} {
	obj := "else " + BlockLeft + Wrap
	obj += sf.ProcessFunctionSupport(ctx.AllFunctionSupportStatement())
	obj += BlockRight
	return obj
}
