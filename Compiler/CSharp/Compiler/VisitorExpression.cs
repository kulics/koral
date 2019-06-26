using Library;
using static Library.Lib;
using Antlr4.Runtime;
using Antlr4.Runtime.Misc;
using System;
using static Compiler.XsParser;
using static Compiler.Compiler_Static;

namespace Compiler
{
public partial class TemplateItem
{
public  virtual  string Template { get;set; }
public  virtual  string Contract { get;set; }
};
public partial class DicEle
{
public  virtual  string key { get;set; }
public  virtual  string value { get;set; }
public  virtual  string text { get;set; }
};
public partial class XsLangVisitor{
public  override  object VisitVariableStatement( VariableStatementContext context )
{
var obj = "";
var r1 = ((Result)(Visit(context.expression(0))));
var r2 = ((Result)(Visit(context.expression(1))));
if ( context.typeType()!=null ) {
var Type = ((string)(Visit(context.typeType())));
obj=(new System.Text.StringBuilder("").Append(Type).Append(" ").Append(r1.text).Append(" = ").Append(r2.text).Append("")).to_Str()+Terminate+Wrap;
}
else {
obj=(new System.Text.StringBuilder("var ").Append(r1.text).Append(" = ").Append(r2.text).Append("")).to_Str()+Terminate+Wrap;
}
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitVariableDeclaredStatement( VariableDeclaredStatementContext context )
{
var obj = "";
var Type = ((string)(Visit(context.typeType())));
var r = ((Result)(Visit(context.expression())));
obj=(new System.Text.StringBuilder("").Append(Type).Append(" ").Append(r.text).Append("")).to_Str()+Terminate+Wrap;
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitAssignStatement( AssignStatementContext context )
{
var r1 = ((Result)(Visit(context.expression(0))));
var r2 = ((Result)(Visit(context.expression(1))));
var obj = r1.text+Visit(context.assign())+r2.text+Terminate+Wrap;
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitAssign( AssignContext context )
{
return (context.op.Text) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitExpressionStatement( ExpressionStatementContext context )
{
var r = ((Result)(Visit(context.expression())));
return (r.text+Terminate+Wrap) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitExpression( ExpressionContext context )
{
var count = context.ChildCount;
var r = (new Result());
if ( count==3 ) {
var e1 = ((Result)(Visit(context.GetChild(0))));
var e2 = Visit(context.GetChild(2));
var op = Visit(context.GetChild(1));
switch (context.GetChild(1)) {
case JudgeTypeContext it :
{ r.data=Bool;
var e3 = ((string)(Visit(context.GetChild(2))));
switch (op) {
case "==" :
{ r.text=(new System.Text.StringBuilder("(").Append(e1.text).Append(" is ").Append(e3).Append(")")).to_Str();
} break;
case "><" :
{ r.text=(new System.Text.StringBuilder("!(").Append(e1.text).Append(" is ").Append(e3).Append(")")).to_Str();
} break;
} 
return (r) ; 
} break;
case JudgeContext it :
{ r.data=Bool;
} break;
case AddContext it :
{ if ( ((string)(e1.data))==Str||((string)(((Result)(e2)).data))==Str ) {
r.data=Str;
}
else if ( ((string)(e1.data))==I32&&((string)(((Result)(e2)).data))==I32 ) {
r.data=I32;
} 
else {
r.data=F64;
}
} break;
case MulContext it :
{ if ( ((string)(e1.data))==I32&&((string)(((Result)(e2)).data))==I32 ) {
r.data=I32;
}
else {
r.data=F64;
}
} break;
case PowContext it :
{ r.data=F64;
switch (op) {
case "**" :
{ op="Pow";
} break;
case "//" :
{ op="Root";
} break;
case "%%" :
{ op="Log";
} break;
} 
r.text=(new System.Text.StringBuilder("").Append(op).Append("(").Append(e1.text).Append(", ").Append(((Result)(e2)).text).Append(")")).to_Str();
return (r) ; 
} break;
} 
r.text=e1.text+op+((Result)(e2)).text;
}
else if ( count==2 ) {
r=((Result)(Visit(context.GetChild(0))));
if ( context.GetChild(1).GetType()==typeof(TypeConversionContext) ) {
var e2 = ((string)(Visit(context.GetChild(1))));
r.data=e2;
r.text=(new System.Text.StringBuilder("((").Append(e2).Append(")(").Append(r.text).Append("))")).to_Str();
}
else {
if ( context.op.Type==XsParser.Bang ) {
r.text=(new System.Text.StringBuilder("ref ").Append(r.text).Append("")).to_Str();
}
else if ( context.op.Type==XsParser.Question ) {
r.text+="?";
} 
}
} 
else if ( count==1 ) {
r=((Result)(Visit(context.GetChild(0))));
} 
return (r) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitCallExpression( CallExpressionContext context )
{
var count = context.ChildCount;
var r = (new Result());
if ( count==3 ) {
var e1 = ((Result)(Visit(context.GetChild(0))));
var op = Visit(context.GetChild(1));
var e2 = ((Result)(Visit(context.GetChild(2))));
r.text=e1.text+op+e2.text;
}
else if ( count==1 ) {
r=((Result)(Visit(context.GetChild(0))));
} 
return (r) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTypeConversion( TypeConversionContext context )
{
return (((string)(Visit(context.typeType())))) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitCall( CallContext context )
{
return (context.op.Text) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitWave( WaveContext context )
{
return (context.op.Text) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitJudgeType( JudgeTypeContext context )
{
return (context.op.Text) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitJudge( JudgeContext context )
{
if ( context.op.Text=="><" ) {
return ("!=") ; 
}
else if ( context.op.Text=="&" ) {
return ("&&") ; 
} 
else if ( context.op.Text=="|" ) {
return ("||") ; 
} 
return (context.op.Text) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitAdd( AddContext context )
{
return (context.op.Text) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitMul( MulContext context )
{
return (context.op.Text) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitPow( PowContext context )
{
return (context.op.Text) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitPrimaryExpression( PrimaryExpressionContext context )
{
if ( context.ChildCount==1 ) {
var c = context.GetChild(0);
if ( (c is DataStatementContext) ) {
return (Visit(context.dataStatement())) ; 
}
else if ( (c is IdContext) ) {
return (Visit(context.id())) ; 
} 
else if ( context.t.Type==Discard ) {
return ((new Result(){text = "_",data = "var"})) ; 
} 
}
else if ( context.ChildCount==2 ) {
var id = ((Result)(Visit(context.id())));
var template = ((string)(Visit(context.templateCall())));
return ((new Result(){text = id.text+template,data = id.text+template})) ; 
} 
var r = ((Result)(Visit(context.expression())));
return ((new Result(){text = "("+r.text+")",data = r.data})) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitExpressionList( ExpressionListContext context )
{
var r = (new Result());
var obj = "";
foreach (var i in Range(0,context.expression().Length,1,true,false)){
var temp = ((Result)(Visit(context.expression(i))));
if ( i==0 ) {
obj+=temp.text;
}
else {
obj+=", "+temp.text;
}
} ;
r.text=obj;
r.data="var";
return (r) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTemplateDefine( TemplateDefineContext context )
{
var item = (new TemplateItem());
item.Template+="<";
foreach (var i in Range(0,context.templateDefineItem().Length,1,true,false)){
if ( i>0 ) {
item.Template+=",";
if ( item.Contract.len()>0 ) {
item.Contract+=",";
}
}
var r = ((TemplateItem)(Visit(context.templateDefineItem(i))));
item.Template+=r.Template;
item.Contract+=r.Contract;
} ;
item.Template+=">";
return (item) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTemplateDefineItem( TemplateDefineItemContext context )
{
var item = (new TemplateItem());
if ( context.id().len()==1 ) {
var id1 = context.id(0).GetText();
item.Template=id1;
}
else {
var id1 = context.id(0).GetText();
item.Template=id1;
var id2 = context.id(1).GetText();
item.Contract=(new System.Text.StringBuilder(" where ").Append(id1).Append(":").Append(id2).Append("")).to_Str();
}
return (item) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTemplateCall( TemplateCallContext context )
{
var obj = "";
obj+="<";
foreach (var i in Range(0,context.typeType().Length,1,true,false)){
if ( i>0 ) {
obj+=",";
}
var r = Visit(context.typeType(i));
obj+=r;
} ;
obj+=">";
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitCallElement( CallElementContext context )
{
var id = ((Result)(Visit(context.id())));
if ( context.op?.Type==XsParser.Question ) {
id.text+="?";
}
if ( context.expression()==null ) {
return ((new Result(){text = id.text+((string)(Visit(context.slice())))})) ; 
}
var r = ((Result)(Visit(context.expression())));
r.text=(new System.Text.StringBuilder("").Append(id.text).Append("[").Append(r.text).Append("]")).to_Str();
return (r) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitSlice( SliceContext context )
{
return (((string)(Visit(context.GetChild(0))))) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitSliceFull( SliceFullContext context )
{
var order = "";
var attach = "";
switch (context.op.Text) {
case "<=" :
{ order="true";
attach="true";
} break;
case "<" :
{ order="true";
} break;
case ">=" :
{ order="false";
attach="true";
} break;
case ">" :
{ order="false";
} break;
} 
var expr1 = ((Result)(Visit(context.expression(0))));
var expr2 = ((Result)(Visit(context.expression(1))));
return ((new System.Text.StringBuilder(".slice(").Append(expr1.text).Append(", ").Append(expr2.text).Append(", ").Append(order).Append(", ").Append(attach).Append(")")).to_Str()) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitSliceStart( SliceStartContext context )
{
var order = "";
var attach = "";
switch (context.op.Text) {
case "<=" :
{ order="true";
attach="true";
} break;
case "<" :
{ order="true";
} break;
case ">=" :
{ order="false";
attach="true";
} break;
case ">" :
{ order="false";
} break;
} 
var expr = ((Result)(Visit(context.expression())));
return ((new System.Text.StringBuilder(".slice(").Append(expr.text).Append(", null, ").Append(order).Append(", ").Append(attach).Append(")")).to_Str()) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitSliceEnd( SliceEndContext context )
{
var order = "";
var attach = "false";
switch (context.op.Text) {
case "<=" :
{ order="true";
attach="true";
} break;
case "<" :
{ order="true";
} break;
case ">=" :
{ order="false";
attach="true";
} break;
case ">" :
{ order="false";
} break;
} 
var expr = ((Result)(Visit(context.expression())));
return ((new System.Text.StringBuilder(".slice(null, ").Append(expr.text).Append(", ").Append(order).Append(", ").Append(attach).Append(")")).to_Str()) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitCallFunc( CallFuncContext context )
{
var r = (new Result(){data = "var"});
var id = ((Result)(Visit(context.id())));
r.text+=id.text;
if ( context.templateCall()!=null ) {
r.text+=Visit(context.templateCall());
}
if ( context.tuple()!=null ) {
r.text+=((Result)(Visit(context.tuple()))).text;
}
else {
r.text+=(new System.Text.StringBuilder("(").Append(((Result)(Visit(context.lambda()))).text).Append(")")).to_Str();
}
return (r) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitCallPkg( CallPkgContext context )
{
var r = (new Result(){data = Visit(context.typeType())});
r.text=(new System.Text.StringBuilder("(new ").Append(Visit(context.typeType())).Append("()")).to_Str();
if ( context.pkgAssign()!=null ) {
r.text+=Visit(context.pkgAssign());
}
else if ( context.listAssign()!=null ) {
r.text+=Visit(context.listAssign());
} 
else if ( context.setAssign()!=null ) {
r.text+=Visit(context.setAssign());
} 
else if ( context.dictionaryAssign()!=null ) {
r.text+=Visit(context.dictionaryAssign());
} 
r.text+=")";
return (r) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitCallNew( CallNewContext context )
{
var r = (new Result(){data = Visit(context.typeType())});
var param = "";
if ( context.expressionList()!=null ) {
param=((Result)(Visit(context.expressionList()))).text;
}
r.text=(new System.Text.StringBuilder("(new ").Append(Visit(context.typeType())).Append("(").Append(param).Append(")")).to_Str();
r.text+=")";
return (r) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitPkgAssign( PkgAssignContext context )
{
var obj = "";
obj+="{";
foreach (var i in Range(0,context.pkgAssignElement().Length,1,true,false)){
if ( i==0 ) {
obj+=Visit(context.pkgAssignElement(i));
}
else {
obj+=","+Visit(context.pkgAssignElement(i));
}
} ;
obj+="}";
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitListAssign( ListAssignContext context )
{
var obj = "";
obj+="{";
foreach (var i in Range(0,context.expression().Length,1,true,false)){
var r = ((Result)(Visit(context.expression(i))));
if ( i==0 ) {
obj+=r.text;
}
else {
obj+=","+r.text;
}
} ;
obj+="}";
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitSetAssign( SetAssignContext context )
{
var obj = "";
obj+="{";
foreach (var i in Range(0,context.expression().Length,1,true,false)){
var r = ((Result)(Visit(context.expression(i))));
if ( i==0 ) {
obj+=r.text;
}
else {
obj+=","+r.text;
}
} ;
obj+="}";
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitDictionaryAssign( DictionaryAssignContext context )
{
var obj = "";
obj+="{";
foreach (var i in Range(0,context.dictionaryElement().Length,1,true,false)){
var r = ((DicEle)(Visit(context.dictionaryElement(i))));
if ( i==0 ) {
obj+=r.text;
}
else {
obj+=","+r.text;
}
} ;
obj+="}";
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitPkgAssignElement( PkgAssignElementContext context )
{
var obj = "";
obj+=Visit(context.name())+" = "+((Result)(Visit(context.expression()))).text;
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitPkgAnonymous( PkgAnonymousContext context )
{
return ((new Result(){data = "var",text = "new"+((string)(Visit(context.pkgAnonymousAssign())))})) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitPkgAnonymousAssign( PkgAnonymousAssignContext context )
{
var obj = "";
obj+="{";
foreach (var i in Range(0,context.pkgAnonymousAssignElement().Length,1,true,false)){
if ( i==0 ) {
obj+=Visit(context.pkgAnonymousAssignElement(i));
}
else {
obj+=","+Visit(context.pkgAnonymousAssignElement(i));
}
} ;
obj+="}";
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitPkgAnonymousAssignElement( PkgAnonymousAssignElementContext context )
{
var obj = "";
obj+=Visit(context.name())+" = "+((Result)(Visit(context.expression()))).text;
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitCallAwait( CallAwaitContext context )
{
var r = (new Result());
var expr = ((Result)(Visit(context.expression())));
r.data="var";
r.text="await "+expr.text;
return (r) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitList( ListContext context )
{
var type = "object";
var result = (new Result());
foreach (var i in Range(0,context.expression().Length,1,true,false)){
var r = ((Result)(Visit(context.expression(i))));
if ( i==0 ) {
type=((string)(r.data));
result.text+=r.text;
}
else {
if ( type!=((string)(r.data)) ) {
type="object";
}
result.text+=","+r.text;
}
} ;
result.data=(new System.Text.StringBuilder("Lst<").Append(type).Append(">")).to_Str();
result.text=(new System.Text.StringBuilder("(new ").Append(result.data).Append("(){ ").Append(result.text).Append(" })")).to_Str();
return (result) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitSet( SetContext context )
{
var type = "object";
var result = (new Result());
foreach (var i in Range(0,context.expression().Length,1,true,false)){
var r = ((Result)(Visit(context.expression(i))));
if ( i==0 ) {
type=((string)(r.data));
result.text+=r.text;
}
else {
if ( type!=((string)(r.data)) ) {
type="object";
}
result.text+=","+r.text;
}
} ;
result.data=(new System.Text.StringBuilder("Set<").Append(type).Append(">")).to_Str();
result.text=(new System.Text.StringBuilder("(new ").Append(result.data).Append("(){ ").Append(result.text).Append(" })")).to_Str();
return (result) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitDictionary( DictionaryContext context )
{
var key = Any;
var value = Any;
var result = (new Result());
foreach (var i in Range(0,context.dictionaryElement().Length,1,true,false)){
var r = ((DicEle)(Visit(context.dictionaryElement(i))));
if ( i==0 ) {
key=r.key;
value=r.value;
result.text+=r.text;
}
else {
if ( key!=r.key ) {
key=Any;
}
if ( value!=r.value ) {
value=Any;
}
result.text+=","+r.text;
}
} ;
var type = key+","+value;
result.data=(new System.Text.StringBuilder("Dic<").Append(type).Append(">")).to_Str();
result.text=(new System.Text.StringBuilder("(new ").Append(result.data).Append("(){ ").Append(result.text).Append(" })")).to_Str();
return (result) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitDictionaryElement( DictionaryElementContext context )
{
var r1 = ((Result)(Visit(context.expression(0))));
var r2 = ((Result)(Visit(context.expression(1))));
var result = (new DicEle(){key = ((string)(r1.data)),value = ((string)(r2.data)),text = "{"+r1.text+","+r2.text+"}"});
return (result) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitStringExpression( StringExpressionContext context )
{
var text = (new System.Text.StringBuilder("(new System.Text.StringBuilder(").Append(context.TextLiteral().GetText()).Append(")")).to_Str();
foreach (var item in context.stringExpressionElement()){
text+=Visit(item);
} ;
text+=").to_Str()";
return ((new Result(){data = Str,text = text})) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitStringExpressionElement( StringExpressionElementContext context )
{
var r = ((Result)(Visit(context.expression())));
var text = context.TextLiteral().GetText();
return ((new System.Text.StringBuilder(".Append(").Append(r.text).Append(").Append(").Append(text).Append(")")).to_Str()) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitDataStatement( DataStatementContext context )
{
var r = (new Result());
if ( context.nilExpr()!=null ) {
r.data=Any;
r.text="null";
}
else if ( context.floatExpr()!=null ) {
r.data=F64;
r.text=((string)(Visit(context.floatExpr())));
} 
else if ( context.integerExpr()!=null ) {
r.data=I32;
r.text=((string)(Visit(context.integerExpr())));
} 
else if ( context.t.Type==TextLiteral ) {
r.data=Str;
r.text=context.TextLiteral().GetText();
} 
else if ( context.t.Type==XsParser.CharLiteral ) {
r.data=Chr;
r.text=context.CharLiteral().GetText();
} 
else if ( context.t.Type==XsParser.TrueLiteral ) {
r.data=Bool;
r.text=T;
} 
else if ( context.t.Type==XsParser.FalseLiteral ) {
r.data=Bool;
r.text=F;
} 
return (r) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitFloatExpr( FloatExprContext context )
{
var number = "";
number+=Visit(context.integerExpr(0))+"."+Visit(context.integerExpr(1));
return (number) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitIntegerExpr( IntegerExprContext context )
{
var number = "";
foreach (var item in context.NumberLiteral()){
number+=item.GetText();
} ;
return (number) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitFunctionExpression( FunctionExpressionContext context )
{
var r = (new Result());
if ( context.t.Type==Right_Flow ) {
r.text+=" async ";
}
r.text+=Visit(context.parameterClauseIn())+" => "+BlockLeft+Wrap;
r.text+=ProcessFunctionSupport(context.functionSupportStatement());
r.text+=BlockRight+Wrap;
r.data="var";
return (r) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitLambda( LambdaContext context )
{
var r = (new Result(){data = "var"});
if ( context.t.Type==Right_Flow ) {
r.text+="async ";
}
r.text+="(";
if ( context.lambdaIn()!=null ) {
r.text+=Visit(context.lambdaIn());
}
r.text+=")";
r.text+="=>";
if ( context.expressionList()!=null ) {
r.text+=((Result)(Visit(context.expressionList()))).text;
}
else {
r.text+="{"+ProcessFunctionSupport(context.functionSupportStatement())+"}";
}
return (r) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitLambdaIn( LambdaInContext context )
{
var obj = "";
foreach (var i in Range(0,context.id().Length,1,true,false)){
var r = ((Result)(Visit(context.id(i))));
if ( i==0 ) {
obj+=r.text;
}
else {
obj+=", "+r.text;
}
} ;
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitPlusMinus( PlusMinusContext context )
{
var r = (new Result());
var expr = ((Result)(Visit(context.expression())));
var op = Visit(context.add());
r.data=expr.data;
r.text=op+expr.text;
return (r) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitNegate( NegateContext context )
{
var r = (new Result());
var expr = ((Result)(Visit(context.expression())));
r.data=expr.data;
r.text="!"+expr.text;
return (r) ; 
}
}
public partial class Compiler_Static{
public static Lst<string> keywords = (new Lst<string>(){"abstract","as","base","bool","break","byte","case","catch","char","checked","class","const","continue","decimal","default","delegate","do","double","_","enum","event","explicit","extern","false","finally","fixed","float","for","foreach","goto","?","implicit","in","int","interface","internal","is","lock","long","namespace","new","null","object","operator","out","override","params","private","protected","public","readonly","ref","return","sbyte","sealed","short","sizeof","stackalloc","static","string","struct","switch","this","throw","true","try","typeof","uint","ulong","unchecked","unsafe","ushort","using","virtual","void","volatile","while"}) ;
}
}
