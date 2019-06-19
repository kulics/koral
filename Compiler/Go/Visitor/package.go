package visitor

import (
	"xs/parser"

	"github.com/antlr/antlr4/runtime/Go/antlr"
)

func (sf *XsVisitor) VisitIncludeStatement(ctx *parser.IncludeStatementContext) interface{} {
	return sf.Visit(ctx.TypeType()).(string) + Wrap
}

func (sf *XsVisitor) VisitPackageStatement(ctx *parser.PackageStatementContext) interface{} {
	id := sf.Visit(ctx.Id()).(Result)
	obj := ""
	Init := ""

	// # 处理构造函数 #
	// ctx.packageNewStatement() @ item {
	// 	Init += "public " id.text " " Visit(item):Str ""
	// }
	for _, item := range ctx.AllPackageSupportStatement() {
		obj += sf.Visit(item).(string)
	}
	obj = Init + obj
	obj += BlockRight + Wrap
	header := ""
	if ctx.AnnotationSupport() != nil {
		header += sf.Visit(ctx.AnnotationSupport()).(string)
	}
	header += "type " + id.Text + " struct"
	// # 泛型 #
	// template := ""
	templateContract := ""
	// ? ctx.templateDefine() >< () {
	// 	item := Visit(ctx.templateDefine()):TemplateItem
	// 	template += item.Template
	// 	templateContract = item.Contract
	// 	header += template;
	// }

	header += templateContract + BlockLeft + Wrap
	obj = header + obj

	return obj
}

func (sf *XsVisitor) VisitPackageSupportStatement(ctx *parser.PackageSupportStatementContext) interface{} {
	return sf.Visit(ctx.GetChild(0).(antlr.ParseTree))
}

func (sf *XsVisitor) VisitPackageVariableStatement(ctx *parser.PackageVariableStatementContext) interface{} {
	r1 := sf.Visit(ctx.Id()).(Result)
	typ := ""
	// r2:= Result{}
	// if ctx.Expression() != nil {
	// 	r2 = Visit(ctx.expression()).(Result)
	// 	typ = r2.data:Str
	// }
	if ctx.TypeType() != nil {
		typ = sf.Visit(ctx.TypeType()).(string)
	}
	obj := ""
	if ctx.AnnotationSupport() != nil {
		obj += sf.Visit(ctx.AnnotationSupport()).(string)
	}

	obj += r1.Text + " " + typ
	// if r2 != nil {
	// 	obj += " = " + r2.text
	// }
	obj += Wrap
	return obj
}

func (sf *XsVisitor) VisitPackageFunctionStatement(ctx *parser.PackageFunctionStatementContext) interface{} {
	id := sf.Visit(ctx.Id()).(Result)
	obj := ""
	// if ctx.AnnotationSupport() >< () {
	// 	obj += Visit(context.annotationSupport())
	// }
	// 异步
	// if ctx.GetT().GetTokenType() == parser.XsLexerRight_Flow {
	// pout := Visit(ctx.ParameterClauseOut()).(string)
	// obj += ""id.permission" async static "pout" "id.text""
	// } else {
	// 	obj += Func + id.Text  + sf.Visit(ctx.ParameterClauseOut()).(string)
	// }

	// 泛型
	// templateContract := ""
	// if context.templateDefine() >< () {
	// 	template := Visit(context.templateDefine()):TemplateItem
	// 	obj += template.Template
	// 	templateContract = template.Contract
	// }
	Self := sf.Visit(ctx.ParameterClauseSelf()).(Parameter)
	obj += Func + "(" + Self.Id + " " + Self.Type + ")" +
		id.Text + sf.Visit(ctx.ParameterClauseIn()).(string) +
		sf.Visit(ctx.ParameterClauseOut()).(string) + BlockLeft + Wrap
	obj += sf.ProcessFunctionSupport(ctx.AllFunctionSupportStatement())
	obj += BlockRight + Wrap
	return obj
}
