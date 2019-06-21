package visitor

import (
	"fmt"
	"xs/parser"

	"github.com/antlr/antlr4/runtime/Go/antlr"
)

const (
	Wrap      = "\r\n"
	Terminate = ";"

	Any = "interface{}"
	Int = "int"
	Num = "float64"
	I8  = "int8"
	I16 = "int16"
	I32 = "int32"
	I64 = "int64"

	U8  = "uint8"
	U16 = "uint16"
	U32 = "uint32"
	U64 = "uint64"

	F32 = "float32"
	F64 = "float64"

	Bool = "bool"
	T    = "true"
	F    = "false"

	Chr = "rune"
	Str = "string"
	Lst = "Lst"
	Set = "Set"
	Dic = "Dic"

	BlockLeft  = "{"
	BlockRight = "}"

	Func  = "func "
	Var   = "var "
	Const = "const "
	Type  = "type "
	Chan  = "chan "
)

type errorListener struct {
	*antlr.DefaultErrorListener

	file string
	Err  error
}

func NewErrorListener(file string) *errorListener {
	return &errorListener{
		file: file,
	}
}

func (sf *errorListener) Error() string {
	if sf.Err == nil {
		return ""
	}
	return sf.Err.Error()
}

func (sf *errorListener) SyntaxError(recognizer antlr.Recognizer, offendingSymbol interface{}, line, column int, msg string, e antlr.RecognitionException) {
	sf.Err = fmt.Errorf("[ERR %s:%d:%d] %s", sf.file, line, column, msg)
}

type XsVisitor struct {
	parser.BaseXsParserVisitor
}

type Result struct {
	Data       interface{}
	Text       string
	Permission string
	IsVirtual  bool
}

func (sf *XsVisitor) Visit(tree antlr.ParseTree) interface{} {
	return tree.Accept(sf)
}

func (sf *XsVisitor) VisitChildren(tree antlr.RuleNode) interface{} {
	return tree.Accept(sf)
}

// func (sf *XsVisitor) VisitTerminal(tree antlr.TerminalNode) interface{} {
// 	return tree.Accept(sf)
// }

// func (sf *XsVisitor) VisitErrorNode(tree antlr.ErrorNode) interface{} {
// 	return tree.Accept(sf)
// }

func (sf *XsVisitor) VisitProgram(ctx *parser.ProgramContext) interface{} {
	obj := ""
	for _, item := range ctx.AllStatement() {
		obj += sf.Visit(item).(string)
	}
	return obj
}

func (sf *XsVisitor) VisitId(ctx *parser.IdContext) interface{} {
	r := Result{Data: "var"}
	first := sf.Visit(ctx.GetChild(0).(antlr.ParseTree)).(Result)
	r.Permission = first.Permission
	r.Text = first.Text
	r.IsVirtual = first.IsVirtual
	if ctx.GetChildCount() >= 2 {
		for i := 1; i < ctx.GetChildCount(); i++ {
			other := sf.Visit(ctx.GetChild(i).(antlr.ParseTree)).(Result)
			r.Text += "_" + other.Text
		}
	}
	// todo
	// if keywords.Exists({t -> t == r.Text}) {
	// 	r.Text = "@" + r.Text
	// }
	return r
}

func (sf *XsVisitor) VisitIdItem(ctx *parser.IdItemContext) interface{} {
	r := Result{Data: "var"}
	if ctx.TypeBasic() != nil {
		r.Permission = "public"
		r.Text += ctx.TypeBasic().GetText()
	} else if ctx.TypeAny() != nil {
		r.Permission = "public"
		r.Text += ctx.TypeAny().GetText()
	} else if ctx.LinqKeyword() != nil {
		r.Permission = "public"
		r.Text += sf.Visit(ctx.LinqKeyword()).(string)
	} else if ctx.GetOp().GetTokenType() == parser.XsLexerIDPublic {
		r.Permission = "public"
		r.Text += ctx.GetOp().GetText()
		// r.IsVirtual = r.Text[0].is Upper()
	} else if ctx.GetOp().GetTokenType() == parser.XsLexerIDPrivate {
		r.Permission = "protected"
		r.Text += ctx.GetOp().GetText()
		// r.IsVirtual = r.Text[r.Text.find first({it -> it >< '_'})].is Upper()
	}
	return r
}
