using Library;
using static Library.Lib;
using Antlr4.Runtime;
using Antlr4.Runtime.Misc;
using System;
using static Compiler.XsParser;
using static Compiler.Compiler_Static;

namespace Compiler
{
public partial class Iterator
{
public  virtual  Result begin { get;set; }
public  virtual  Result end { get;set; }
public  virtual  Result step { get;set; }
public  virtual  string order { get;set; } = T ; 
public  virtual  string attach { get;set; } = F ; 
};
public partial class XsLangVisitor{
public  override  object VisitIteratorStatement( IteratorStatementContext context )
{
var it = (new Iterator());
if ( context.op.Text==">="||context.op.Text=="<=" ) {
it.attach=T;
}
if ( context.op.Text==">"||context.op.Text==">=" ) {
it.order=F;
}
if ( context.expression().Length==2 ) {
it.begin=((Result)(Visit(context.expression(0))));
it.end=((Result)(Visit(context.expression(1))));
it.step=(new Result(){data = I32,text = "1"});
}
else {
it.begin=((Result)(Visit(context.expression(0))));
it.end=((Result)(Visit(context.expression(1))));
it.step=((Result)(Visit(context.expression(2))));
}
return (it) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitLoopStatement( LoopStatementContext context )
{
var obj = "";
var id = "ea";
if ( context.id()!=null ) {
id=((Result)(Visit(context.id()))).text;
}
var it = ((Iterator)(Visit(context.iteratorStatement())));
obj+=(new System.Text.StringBuilder("foreach (var ").Append(id).Append(" in Range(").Append(it.begin.text).Append(",").Append(it.end.text).Append(",").Append(it.step.text).Append(",").Append(it.order).Append(",").Append(it.attach).Append("))")).to_Str();
obj+=(new System.Text.StringBuilder("").Append(BlockLeft+Wrap).Append("")).to_Str();
obj+=ProcessFunctionSupport(context.functionSupportStatement());
obj+=(new System.Text.StringBuilder("").Append(BlockRight).Append(" ").Append(Terminate+Wrap).Append("")).to_Str();
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitLoopInfiniteStatement( LoopInfiniteStatementContext context )
{
var obj = (new System.Text.StringBuilder("for (;;) ").Append(BlockLeft+Wrap).Append("")).to_Str();
obj+=ProcessFunctionSupport(context.functionSupportStatement());
obj+=(new System.Text.StringBuilder("").Append(BlockRight).Append(" ").Append(Terminate+Wrap).Append("")).to_Str();
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitLoopEachStatement( LoopEachStatementContext context )
{
var obj = "";
var arr = ((Result)(Visit(context.expression())));
var target = arr.text;
var id = "ea";
if ( context.id().Length==2 ) {
target=(new System.Text.StringBuilder("Range(").Append(target).Append(")")).to_Str();
id=(new System.Text.StringBuilder("(").Append(((Result)(Visit(context.id(0)))).text).Append(",").Append(((Result)(Visit(context.id(1)))).text).Append(")")).to_Str();
}
else if ( context.id().Length==1 ) {
id=((Result)(Visit(context.id(0)))).text;
} 
obj+=(new System.Text.StringBuilder("foreach (var ").Append(id).Append(" in ").Append(target).Append(")")).to_Str();
obj+=(new System.Text.StringBuilder("").Append(BlockLeft+Wrap).Append("")).to_Str();
obj+=ProcessFunctionSupport(context.functionSupportStatement());
obj+=(new System.Text.StringBuilder("").Append(BlockRight).Append(" ").Append(Terminate+Wrap).Append("")).to_Str();
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitLoopCaseStatement( LoopCaseStatementContext context )
{
var obj = "";
var expr = ((Result)(Visit(context.expression())));
obj+=(new System.Text.StringBuilder("for ( ;").Append(expr.text).Append(" ;)")).to_Str();
obj+=(new System.Text.StringBuilder("").Append(BlockLeft+Wrap).Append("")).to_Str();
obj+=ProcessFunctionSupport(context.functionSupportStatement());
obj+=(new System.Text.StringBuilder("").Append(BlockRight).Append(" ").Append(Terminate+Wrap).Append("")).to_Str();
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitLoopJumpStatement( LoopJumpStatementContext context )
{
return ((new System.Text.StringBuilder("break ").Append(Terminate+Wrap).Append("")).to_Str()) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitLoopContinueStatement( LoopContinueStatementContext context )
{
return ((new System.Text.StringBuilder("continue ").Append(Terminate+Wrap).Append("")).to_Str()) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitJudgeCaseStatement( JudgeCaseStatementContext context )
{
var obj = "";
var expr = ((Result)(Visit(context.expression())));
obj+=(new System.Text.StringBuilder("switch (").Append(expr.text).Append(") ").Append(BlockLeft+Wrap).Append("")).to_Str();
foreach (var item in context.caseStatement()){
var r = ((string)(Visit(item)));
obj+=r+Wrap;
} ;
obj+=(new System.Text.StringBuilder("").Append(BlockRight).Append(" ").Append(Wrap).Append("")).to_Str();
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitCaseDefaultStatement( CaseDefaultStatementContext context )
{
var obj = "";
obj+=(new System.Text.StringBuilder("default:").Append(BlockLeft+Wrap).Append("")).to_Str();
obj+=ProcessFunctionSupport(context.functionSupportStatement());
obj+=(new System.Text.StringBuilder("").Append(BlockRight).Append("break;")).to_Str();
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitCaseExprStatement( CaseExprStatementContext context )
{
var obj = "";
if ( context.typeType()==null ) {
var expr = ((Result)(Visit(context.expression())));
obj+=(new System.Text.StringBuilder("case ").Append(expr.text).Append(" :").Append(Wrap).Append("")).to_Str();
}
else {
var id = "it";
if ( context.id()!=null ) {
id=((Result)(Visit(context.id()))).text;
}
var type = ((string)(Visit(context.typeType())));
obj+=(new System.Text.StringBuilder("case ").Append(type).Append(" ").Append(id).Append(" :").Append(Wrap).Append("")).to_Str();
}
obj+=(new System.Text.StringBuilder("").Append(BlockLeft).Append(" ").Append(ProcessFunctionSupport(context.functionSupportStatement())).Append("").Append(BlockRight).Append(" ")).to_Str();
obj+="break;";
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitCaseStatement( CaseStatementContext context )
{
var obj = ((string)(Visit(context.GetChild(0))));
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitJudgeStatement( JudgeStatementContext context )
{
var obj = "";
obj+=Visit(context.judgeIfStatement());
foreach (var it in context.judgeElseIfStatement()){
obj+=Visit(it);
} ;
if ( context.judgeElseStatement()!=null ) {
obj+=Visit(context.judgeElseStatement());
}
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitJudgeIfStatement( JudgeIfStatementContext context )
{
var b = ((Result)(Visit(context.expression())));
var obj = (new System.Text.StringBuilder("if ( ").Append(b.text).Append(" ) ").Append(BlockLeft+Wrap).Append("")).to_Str();
obj+=ProcessFunctionSupport(context.functionSupportStatement());
obj+=(new System.Text.StringBuilder("").Append(BlockRight).Append("").Append(Wrap).Append("")).to_Str();
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitJudgeElseIfStatement( JudgeElseIfStatementContext context )
{
var b = ((Result)(Visit(context.expression())));
var obj = (new System.Text.StringBuilder("else if ( ").Append(b.text).Append(" ) ").Append(BlockLeft+Wrap).Append("")).to_Str();
obj+=ProcessFunctionSupport(context.functionSupportStatement());
obj+=(new System.Text.StringBuilder("").Append(BlockRight).Append(" ").Append(Wrap).Append("")).to_Str();
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitJudgeElseStatement( JudgeElseStatementContext context )
{
var obj = (new System.Text.StringBuilder("else ").Append(BlockLeft+Wrap).Append("")).to_Str();
obj+=ProcessFunctionSupport(context.functionSupportStatement());
obj+=(new System.Text.StringBuilder("").Append(BlockRight).Append("").Append(Wrap).Append("")).to_Str();
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitCheckStatement( CheckStatementContext context )
{
var obj = (new System.Text.StringBuilder("try ").Append(BlockLeft+Wrap).Append("")).to_Str();
obj+=ProcessFunctionSupport(context.functionSupportStatement());
obj+=(new System.Text.StringBuilder("").Append(BlockRight+Wrap).Append("")).to_Str();
foreach (var item in context.checkErrorStatement()){
obj+=(new System.Text.StringBuilder("").Append(Visit(item)).Append("").Append(Wrap).Append("")).to_Str();
} ;
if ( context.checkFinallyStatment()!=null ) {
obj+=Visit(context.checkFinallyStatment());
}
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitCheckErrorStatement( CheckErrorStatementContext context )
{
var obj = "";
var ID = "ex";
if ( context.id()!=null ) {
ID=((Result)(Visit(context.id()))).text;
}
var Type = "Exception";
if ( context.typeType()!=null ) {
Type=((string)(Visit(context.typeType())));
}
obj+=(new System.Text.StringBuilder("catch( ").Append(Type).Append(" ").Append(ID).Append(" )")).to_Str()+Wrap+BlockLeft+Wrap;
obj+=ProcessFunctionSupport(context.functionSupportStatement());
obj+=BlockRight;
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitCheckFinallyStatment( CheckFinallyStatmentContext context )
{
var obj = (new System.Text.StringBuilder("finally ").Append(Wrap+BlockLeft+Wrap).Append("")).to_Str();
obj+=ProcessFunctionSupport(context.functionSupportStatement());
obj+=(new System.Text.StringBuilder("").Append(BlockRight).Append("").Append(Wrap).Append("")).to_Str();
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitUsingStatement( UsingStatementContext context )
{
var obj = "";
var r2 = ((Result)(Visit(context.expression(0))));
var r1 = ((Result)(Visit(context.expression(1))));
if ( context.typeType()!=null ) {
var Type = ((string)(Visit(context.typeType())));
obj=(new System.Text.StringBuilder("").Append(Type).Append(" ").Append(r1.text).Append(" = ").Append(r2.text).Append("")).to_Str();
}
else {
obj=(new System.Text.StringBuilder("var ").Append(r1.text).Append(" = ").Append(r2.text).Append("")).to_Str();
}
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitReportStatement( ReportStatementContext context )
{
var obj = "";
if ( context.expression()!=null ) {
var r = ((Result)(Visit(context.expression())));
obj+=r.text;
}
return ((new System.Text.StringBuilder("throw ").Append(obj+Terminate+Wrap).Append("")).to_Str()) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitLinq( LinqContext context )
{
var r = (new Result(){data = "var"});
r.text+=(new System.Text.StringBuilder("from ").Append(((Result)(Visit(context.expression(0)))).text).Append(" ")).to_Str();
foreach (var item in context.linqItem()){
r.text+=(new System.Text.StringBuilder("").Append(Visit(item)).Append(" ")).to_Str();
} ;
r.text+=(new System.Text.StringBuilder("").Append(context.k.Text).Append(" ").Append(((Result)(Visit(context.expression(1)))).text).Append("")).to_Str();
return (r) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitLinqItem( LinqItemContext context )
{
var obj = ((string)(Visit(context.linqKeyword())));
if ( context.expression()!=null ) {
obj+=(new System.Text.StringBuilder(" ").Append(((Result)(Visit(context.expression()))).text).Append("")).to_Str();
}
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitLinqKeyword( LinqKeywordContext context )
{
return (Visit(context.GetChild(0))) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitLinqHeadKeyword( LinqHeadKeywordContext context )
{
return (context.k.Text) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitLinqBodyKeyword( LinqBodyKeywordContext context )
{
return (context.k.Text) ; 
}
}
}
