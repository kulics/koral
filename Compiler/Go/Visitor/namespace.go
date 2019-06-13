package visitor

import (
	"fmt"

	"xs/parser"

	"github.com/antlr/antlr4/runtime/Go/antlr"
)

type Namespace struct {
	Name    string
	Imports string
}

func (sf *XsVisitor) VisitStatement(ctx *parser.StatementContext) interface{} {
	obj := ""
	ns, ok := sf.Visit(ctx.ExportStatement()).(*Namespace)
	if !ok {
		return ""
	}
	obj += fmt.Sprintf("package %s%s", ns.Name, Wrap)
	for _, item := range ctx.AllNamespaceSupportStatement() {
		if v, ok := sf.Visit(item).(string); ok {
			obj += v
		}
	}
	return obj
}

func (sf *XsVisitor) VisitExportStatement(ctx *parser.ExportStatementContext) interface{} {
	obj := &Namespace{
		Name: sf.Visit(ctx.NameSpace()).(string),
	}
	for _, item := range ctx.AllImportStatement() {
		obj.Imports += sf.Visit(item).(string)
	}
	return obj
}

func (sf *XsVisitor) VisitNameSpace(ctx *parser.NameSpaceContext) interface{} {
	obj := ""
	for i := 0; i < len(ctx.AllId()); i++ {
		id := sf.Visit(ctx.Id(i)).(Result)
		if i == 0 {
			obj += "" + id.Text
		} else {
			obj += "." + id.Text
		}
	}
	return obj
}

func (sf *XsVisitor) VisitNameSpaceItem(ctx *parser.NameSpaceItemContext) interface{} {
	obj := ""
	for i := 0; i < len(ctx.AllId()); i++ {
		id := sf.Visit(ctx.Id(i)).(Result)
		if i == 0 {
			obj += "" + id.Text
		} else {
			obj += "." + id.Text
		}
	}
	return obj
}

func (sf *XsVisitor) VisitNamespaceSupportStatement(ctx *parser.NamespaceSupportStatementContext) interface{} {
	return sf.Visit(ctx.GetChild(0).(antlr.ParseTree))
}

func (sf *XsVisitor) VisitNamespaceFunctionStatement(ctx *parser.NamespaceFunctionStatementContext) interface{} {
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
	obj += Func + id.Text + sf.Visit(ctx.ParameterClauseIn()).(string) + sf.Visit(ctx.ParameterClauseOut()).(string) + BlockLeft + Wrap
	obj += sf.ProcessFunctionSupport(ctx.AllFunctionSupportStatement())
	obj += BlockRight + Wrap
	return obj
}

func (sf *XsVisitor) VisitNamespaceConstantStatement(ctx *parser.NamespaceConstantStatementContext) interface{} {
	id := sf.Visit(ctx.Id()).(Result)
	expr := sf.Visit(ctx.Expression()).(Result)
	typ := ""
	if ctx.TypeType() != nil {
		typ = sf.Visit(ctx.TypeType()).(string)
	}

	obj := ""
	if ctx.AnnotationSupport() != nil {
		obj += sf.Visit(ctx.AnnotationSupport()).(string)
	}

	obj += Const + id.Text + " " + typ + " = " + expr.Text + Wrap
	return obj
}

func (sf *XsVisitor) VisitNamespaceVariableStatement(ctx *parser.NamespaceVariableStatementContext) interface{} {
	r1 := sf.Visit(ctx.Id()).(Result)
	typ := ""

	if ctx.TypeType() != nil {
		typ = sf.Visit(ctx.TypeType()).(string)
	}
	obj := ""
	if ctx.AnnotationSupport() != nil {
		obj += sf.Visit(ctx.AnnotationSupport()).(string)
	}

	obj += Var + r1.Text + " " + typ
	if ctx.Expression() != nil {
		obj += " = " + sf.Visit(ctx.Expression()).(Result).Text + Wrap
	}
	return obj
}
