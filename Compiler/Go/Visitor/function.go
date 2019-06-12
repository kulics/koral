package visitor

import (
	"xs/parser"
)

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
	obj += content
	return obj
}

func (sf *XsVisitor) VisitParameterClauseIn(ctx *parser.ParameterClauseInContext) interface{} {
	return "()"
}

func (sf *XsVisitor) VisitParameterClauseOut(ctx *parser.ParameterClauseOutContext) interface{} {
	return "()"
}
