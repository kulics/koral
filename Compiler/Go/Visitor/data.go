package visitor

import (
	"xs/parser"

	"github.com/antlr/antlr4/runtime/Go/antlr"
)

func (sf *XsVisitor) VisitExpressionStatement(ctx *parser.ExpressionStatementContext) interface{} {
	r := sf.Visit(ctx.Expression()).(Result)
	return r.Text + Wrap
}

func (sf *XsVisitor) VisitExpression(ctx *parser.ExpressionContext) interface{} {
	count := ctx.GetChildCount()
	r := Result{}
	if count == 3 {
		e1 := sf.Visit(ctx.GetChild(0).(antlr.ParseTree)).(Result)
		e2 := sf.Visit(ctx.GetChild(2).(antlr.ParseTree))
		op := sf.Visit(ctx.GetChild(1).(antlr.ParseTree))

		switch ctx.GetChild(1).(type) {
		case parser.JudgeTypeContext:
			// r.data = Bool
			// e3 := sf.Visit(ctx.GetChild(2)).(string)
			// if op == "==" {
			// 	r.text = "(" + e1.text + " is " + e3+")"
			// } else if op == "><" {
			// 	r.text = "!(" + e1.text +" is "+e3+")"
			// }
			return r
		case parser.JudgeContext:
			// todo 如果左右不是bool类型值，报错
			r.Data = Bool
		case parser.AddContext:
			// todo 如果左右不是number或text类型值，报错
			if e1.Data.(string) == Str || e2.(Result).Data.(string) == Str {
				r.Data = Str
			} else if e1.Data.(string) == I32 && e2.(Result).Data.(string) == I32 {
				r.Data = I32
			} else {
				r.Data = F64
			}
		case parser.MulContext:
			// todo 如果左右不是number类型值，报错
			if e1.Data.(string) == I32 && e2.(Result).Data.(string) == I32 {
				r.Data = I32
			} else {
				r.Data = F64
			}
		case parser.PowContext:
			// todo 如果左右部署number类型，报错
			r.Data = F64
			switch op {
			case "**":
				op = "Pow"
			case "//":
				op = "Root"
			case "%%":
				op = "Log"
			}
			r.Text = op.(string) + "(" + e1.Text + ", " + e2.(Result).Text + ")"
			return r
		}
		r.Text = e1.Text + op.(string) + e2.(Result).Text
	} else if count == 2 {
		r = sf.Visit(ctx.GetChild(0).(antlr.ParseTree)).(Result)
		if _, ok := ctx.GetChild(1).(parser.TypeConversionContext); ok {
			e2 := sf.Visit(ctx.GetChild(1).(antlr.ParseTree)).(string)
			r.Data = e2
			r.Text = e2 + "(" + r.Text + ")"
		} else {
			if ctx.GetOp().GetTokenType() == parser.XsLexerBang {
				r.Text = "*" + r.Text
			} else if ctx.GetOp().GetTokenType() == parser.XsLexerQuestion {
				r.Text = "&" + r.Text
			} else if ctx.GetOp().GetTokenType() == parser.XsLexerLeft_Flow {
				r.Text = "go " + r.Text
			}
		}
	} else if count == 1 {
		r = sf.Visit(ctx.GetChild(0).(antlr.ParseTree)).(Result)
	}
	return r
}

func (sf *XsVisitor) VisitVariableStatement(ctx *parser.VariableStatementContext) interface{} {
	obj := ""
	r1 := sf.Visit(ctx.Expression(0)).(Result)
	r2 := sf.Visit(ctx.Expression(1)).(Result)
	Type := ""
	if ctx.TypeType() != nil {
		Type = sf.Visit(ctx.TypeType()).(string)
	}
	obj = Var + r1.Text + " " + Type + " = " + r2.Text + Wrap
	return obj
}

func (sf *XsVisitor) VisitVariableDeclaredStatement(ctx *parser.VariableDeclaredStatementContext) interface{} {
	obj := ""
	Type := sf.Visit(ctx.TypeType()).(string)
	r := sf.Visit(ctx.Expression()).(Result)
	obj = Var + r.Text + " " + Type + Wrap
	return obj
}

func (sf *XsVisitor) VisitChannelAssignStatement(ctx *parser.ChannelAssignStatementContext) interface{} {
	r1 := sf.Visit(ctx.Expression(0)).(Result)
	r2 := sf.Visit(ctx.Expression(1)).(Result)
	obj := r1.Text + "<-" + r2.Text + Wrap
	return obj
}

func (sf *XsVisitor) VisitAssignStatement(ctx *parser.AssignStatementContext) interface{} {
	r1 := sf.Visit(ctx.Expression(0)).(Result)
	r2 := sf.Visit(ctx.Expression(1)).(Result)
	obj := r1.Text + sf.Visit(ctx.Assign()).(string) + r2.Text + Wrap
	return obj
}

func (sf *XsVisitor) VisitAssign(ctx *parser.AssignContext) interface{} {
	return ctx.GetOp().GetText()
}

func (sf *XsVisitor) VisitPrimaryExpression(ctx *parser.PrimaryExpressionContext) interface{} {
	if ctx.GetChildCount() == 1 {
		c := ctx.GetChild(0)
		if _, ok := c.(*parser.DataStatementContext); ok {
			return sf.Visit(ctx.DataStatement())
		} else if _, ok := c.(*parser.IdContext); ok {
			return sf.Visit(ctx.Id())
		} else if ctx.GetT().GetTokenType() == parser.XsLexerDot_Dot {
			return Result{Text: "sf", Data: "var"}
		} else if ctx.GetT().GetTokenType() == parser.XsLexerDiscard {
			return Result{Text: "_", Data: "var"}
		}
	} else if ctx.GetChildCount() == 2 {
		id := sf.Visit(ctx.Id()).(Result)
		template := sf.Visit(ctx.TemplateCall()).(string)
		return Result{Text: id.Text + template, Data: id.Text + template}
	}
	r := sf.Visit(ctx.Expression()).(Result)
	return Result{Text: "(" + r.Text + ")", Data: r.Data}
}

func (sf *XsVisitor) VisitExpressionList(ctx *parser.ExpressionListContext) interface{} {
	r := Result{}
	obj := ""
	for i := 0; i < len(ctx.AllExpression()); i++ {
		temp := sf.Visit(ctx.Expression(i)).(Result)
		if i == 0 {
			obj += temp.Text
		} else {
			obj += ", " + temp.Text
		}
	}
	r.Text = obj
	r.Data = "var"
	return r
}

func (sf *XsVisitor) VisitStringExpression(ctx *parser.StringExpressionContext) interface{} {
	text := "bytes.Buffer{}.WriteString(" + ctx.TextLiteral().GetText() + ")"
	for _, item := range ctx.AllStringExpressionElement() {
		text += sf.Visit(item).(string)
	}
	text += ".String()"
	return Result{
		Data: Str,
		Text: text,
	}
}

func (sf *XsVisitor) VisitStringExpressionElement(ctx *parser.StringExpressionElementContext) interface{} {
	r := sf.Visit(ctx.Expression()).(Result)
	text := ctx.TextLiteral().GetText()
	return ".WriteString(fmt.Sprint(" + r.Text + ").WriteString(" + text + ")"
}

func (sf *XsVisitor) VisitDataStatement(ctx *parser.DataStatementContext) interface{} {
	r := Result{}
	if ctx.NilExpr() != nil {
		r.Data = Any
		r.Text = "nil"
	} else if ctx.FloatExpr() != nil {
		r.Data = F64
		r.Text = sf.Visit(ctx.FloatExpr()).(string)
	} else if ctx.IntegerExpr() != nil {
		r.Data = I32
		r.Text = sf.Visit(ctx.IntegerExpr()).(string)
	} else if ctx.GetT().GetTokenType() == parser.XsLexerTextLiteral {
		r.Data = Str
		r.Text = ctx.TextLiteral().GetText()
	} else if ctx.GetT().GetTokenType() == parser.XsLexerCharLiteral {
		r.Data = Chr
		r.Text = ctx.CharLiteral().GetText()
	} else if ctx.GetT().GetTokenType() == parser.XsLexerTrueLiteral {
		r.Data = Bool
		r.Text = T
	} else if ctx.GetT().GetTokenType() == parser.XsLexerFalseLiteral {
		r.Data = Bool
		r.Text = F
	}
	return r
}

func (sf *XsVisitor) VisitFloatExpr(ctx *parser.FloatExprContext) interface{} {
	number := ""
	number += sf.Visit(ctx.IntegerExpr(0)).(string) + "." + sf.Visit(ctx.IntegerExpr(1)).(string)
	return number
}

func (sf *XsVisitor) VisitIntegerExpr(ctx *parser.IntegerExprContext) interface{} {
	number := ""
	for _, item := range ctx.AllNumberLiteral() {
		number += item.GetText()
	}
	return number
}
