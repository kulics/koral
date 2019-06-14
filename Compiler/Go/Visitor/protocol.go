package visitor

import (
	"xs/parser"

	"github.com/antlr/antlr4/runtime/Go/antlr"
)

func (sf *XsVisitor) VisitProtocolStatement(ctx *parser.ProtocolStatementContext) interface{} {
	id := sf.Visit(ctx.Id()).(Result)
	obj := ""
	interfaceProtocol := ""
	ptclName := id.Text
	if ctx.AnnotationSupport() != nil {
		obj += sf.Visit(ctx.AnnotationSupport()).(string)
	}
	for _, item := range ctx.AllProtocolSupportStatement() {
		if r, ok := sf.Visit(item).(Result); ok {
			interfaceProtocol += r.Text
		} else {
			interfaceProtocol += sf.Visit(item).(string)
		}
	}
	obj += "type " + ptclName + " interface"
	// 泛型
	templateContract := ""
	// ? ctx.templateDefine() >< () {
	// 	template := sf.Visit(ctx.templateDefine()):TemplateItem
	// 	obj += template.Template
	// 	templateContract = template.Contract
	// }
	obj += templateContract + BlockLeft + Wrap
	obj += interfaceProtocol
	obj += BlockRight + Wrap
	return obj
}

func (sf *XsVisitor) VisitProtocolSupportStatement(ctx *parser.ProtocolSupportStatementContext) interface{} {
	return sf.Visit(ctx.GetChild(0).(antlr.ParseTree))
}

func (sf *XsVisitor) VisitProtocolFunctionStatement(ctx *parser.ProtocolFunctionStatementContext) interface{} {
	id := sf.Visit(ctx.Id()).(Result)
	r := Result{}
	if ctx.AnnotationSupport() != nil {
		r.Text += sf.Visit(ctx.AnnotationSupport()).(string)
	}
	r.Permission = "public"
	// # 异步 #
	// ? ctx.t.Type == Right Flow {
	// 	pout := sf.Visit(ctx.parameterClauseOut()):Str
	// 	? pout >< "void" {
	// 		pout = ""Task"<"pout">"
	// 	} _ {
	// 		pout = Task
	// 	}
	// 	r.text += pout + " " + id.text
	// } _ {
	// 	r.text += sf.Visit(ctx.parameterClauseOut()) + " " + id.text
	// }
	// 泛型
	templateContract := ""
	// ? ctx.templateDefine() >< () {
	// 	template := sf.Visit(ctx.templateDefine()):TemplateItem
	// 	r.text += template.Template
	// 	templateContract = template.Contract
	// }
	r.Text += id.Text + sf.Visit(ctx.ParameterClauseIn()).(string) + templateContract + sf.Visit(ctx.ParameterClauseOut()).(string) + Wrap
	return r
}
