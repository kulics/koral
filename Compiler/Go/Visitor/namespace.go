package visitor

import (
	"fmt"

	"xs/parser"
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
	obj += fmt.Sprintf("package %s%s", ns.Name, wrap)
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
		id := sf.Visit(ctx.Id(i)).(*Result)
		if i == 0 {
			obj += "" + id.Text
		} else {
			obj += "." + id.Text
		}
	}
	return obj
}
