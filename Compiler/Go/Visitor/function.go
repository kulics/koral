package visitor

import (
	"xs/parser"

	"github.com/antlr/antlr4/runtime/Go/antlr"
)

type Parameter struct {
	Id         string
	Type       string
	Value      string
	Annotation string
	Permission string
}

func (sf *XsVisitor) ProcessFunctionSupport(items []parser.IFunctionSupportStatementContext) string {
	obj := ""
	content := ""
	// lazy := []string{}
	// for _, item := range items {
	// if item.GetChild(0) == :UsingStatementContext {
	// 	lazy.add("}")
	// 	content += "using (" + sf.Visit(item).(string) + ") " + BlockLeft + Wrap
	// } else {
	// content += sf.Visit(item).(string)
	// }
	// }
	// if lazy.Count > 0 {
	// 	for i := lazy.Count - 1; i >= 0; i-- {
	// 		content += BlockRight
	// 	}
	// }
	for _, item := range items {
		if v, ok := sf.Visit(item).(string); ok {
			content += v
		}
	}
	obj += content
	return obj
}

func (sf *XsVisitor) VisitFunctionStatement(ctx *parser.FunctionStatementContext) interface{} {
	id := sf.Visit(ctx.Id()).(Result)
	obj := ""
	// 异步
	// ? context.t.Type == Right Flow {
	// 	pout := Visit(context.parameterClauseOut()):Str
	// 	? pout >< "void" {
	// 		pout = ""Task"<"pout">"
	// 	} _ {
	// 		pout = Task
	// 	}
	// 	obj += " async "pout" "id.text""
	// } _ {
	// 	obj += ""Visit(context.parameterClauseOut())" "id.text""
	// }
	// # 泛型 #
	templateContract := ""
	// ? context.templateDefine() >< () {
	// 	template := Visit(context.templateDefine()):TemplateItem
	// 	obj += template.Template
	// 	templateContract = template.Contract
	// }
	obj += id.Text + ":=" + Func + sf.Visit(ctx.ParameterClauseIn()).(string) + templateContract +
		sf.Visit(ctx.ParameterClauseOut()).(string) + BlockLeft + Wrap
	obj += sf.ProcessFunctionSupport(ctx.AllFunctionSupportStatement())
	obj += BlockRight + Wrap
	return obj
}

func (sf *XsVisitor) VisitFunctionSupportStatement(ctx *parser.FunctionSupportStatementContext) interface{} {
	return sf.Visit(ctx.GetChild(0).(antlr.ParseTree))
}

func (sf *XsVisitor) VisitReturnStatement(ctx *parser.ReturnStatementContext) interface{} {
	r := sf.Visit(ctx.Tuple()).(Result)
	if r.Text == "()" {
		r.Text = ""
	}
	return "return " + r.Text + Wrap
}

func (sf *XsVisitor) VisitParameterClauseIn(ctx *parser.ParameterClauseInContext) interface{} {
	obj := "("
	temp := []string{}
	for i := len(ctx.AllParameter()) - 1; i >= 0; i-- {
		p := sf.Visit(ctx.Parameter(i)).(Parameter)
		temp = append(temp, p.Annotation+" "+p.Id+" "+p.Type)
	}
	for i := len(temp) - 1; i >= 0; i-- {
		if i == len(temp)-1 {
			obj += temp[i]
		} else {
			obj += ", " + temp[i]
		}
	}
	obj += ")"
	return obj
}

func (sf *XsVisitor) VisitParameterClauseOut(ctx *parser.ParameterClauseOutContext) interface{} {
	obj := "("
	temp := []string{}
	for i := len(ctx.AllParameter()) - 1; i >= 0; i-- {
		p := sf.Visit(ctx.Parameter(i)).(Parameter)
		temp = append(temp, p.Annotation+" "+p.Id+" "+p.Type)
	}
	for i := len(temp) - 1; i >= 0; i-- {
		if i == len(temp)-1 {
			obj += temp[i]
		} else {
			obj += ", " + temp[i]
		}
	}
	obj += ")"
	return obj
}

func (sf *XsVisitor) VisitParameter(ctx *parser.ParameterContext) interface{} {
	p := Parameter{}
	id := sf.Visit(ctx.Id()).(Result)
	p.Id = id.Text
	p.Permission = id.Permission
	if ctx.AnnotationSupport() != nil {
		p.Annotation = sf.Visit(ctx.AnnotationSupport()).(string)
	}
	if ctx.Expression() != nil {
		p.Value = "=" + sf.Visit(ctx.Expression()).(Result).Text
	}
	p.Type = sf.Visit(ctx.TypeType()).(string)
	return p
}

func (sf *XsVisitor) VisitTuple(ctx *parser.TupleContext) interface{} {
	obj := ""
	for i := 0; i < len(ctx.AllExpression()); i++ {
		r := sf.Visit(ctx.Expression(i)).(Result)
		if i == 0 {
			obj += r.Text
		} else {
			obj += ", " + r.Text
		}
	}
	result := Result{Data: "var", Text: obj}
	return result
}

func (sf *XsVisitor) VisitTupleExpression(ctx *parser.TupleExpressionContext) interface{} {
	obj := "("
	for i := 0; i < len(ctx.AllExpression()); i++ {
		r := sf.Visit(ctx.Expression(i)).(Result)
		if i == 0 {
			obj += r.Text
		} else {
			obj += ", " + r.Text
		}
	}
	obj += ")"
	result := Result{Data: "var", Text: obj}
	return result
}
