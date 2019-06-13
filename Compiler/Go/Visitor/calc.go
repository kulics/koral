package visitor

import "xs/parser"

func (sf *XsVisitor) VisitTypeConversion(ctx *parser.TypeConversionContext) interface{} {
	return sf.Visit(ctx.TypeType()).(string)
}

func (sf *XsVisitor) VisitCall(ctx *parser.CallContext) interface{} {
	return ctx.GetOp().GetText()
}

func (sf *XsVisitor) VisitWave(ctx *parser.WaveContext) interface{} {
	return ctx.GetOp().GetText()
}

func (sf *XsVisitor) VisitJudgeType(ctx *parser.JudgeTypeContext) interface{} {
	return ctx.GetOp().GetText()
}

func (sf *XsVisitor) VisitJudge(ctx *parser.JudgeContext) interface{} {
	if ctx.GetOp().GetText() == "><" {
		return "!="
	} else if ctx.GetOp().GetText() == "&" {
		return "&&"
	} else if ctx.GetOp().GetText() == "|" {
		return "||"
	}
	return ctx.GetOp().GetText()
}

func (sf *XsVisitor) VisitAdd(ctx *parser.AddContext) interface{} {
	return ctx.GetOp().GetText()
}

func (sf *XsVisitor) VisitMul(ctx *parser.MulContext) interface{} {
	return ctx.GetOp().GetText()
}

func (sf *XsVisitor) VisitPow(ctx *parser.PowContext) interface{} {
	return ctx.GetOp().GetText()
}

func (sf *XsVisitor) VisitPlusMinus(ctx *parser.PlusMinusContext) interface{} {
	r := Result{}
	expr := sf.Visit(ctx.Expression()).(Result)
	op := sf.Visit(ctx.Add()).(string)
	r.Data = expr.Data
	r.Text = op + expr.Text
	return r
}

func (sf *XsVisitor) VisitNegate(ctx *parser.NegateContext) interface{} {
	r := Result{}
	expr := sf.Visit(ctx.Expression()).(Result)
	r.Data = expr.Data
	r.Text = "!" + expr.Text
	return r
}
