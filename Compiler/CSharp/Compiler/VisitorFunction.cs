using Library;
using static Library.Lib;
using Antlr4.Runtime;
using Antlr4.Runtime.Misc;
using System;
using static Compiler.XsParser;
using static Compiler.Compiler_Static;

namespace Compiler
{
public partial class Parameter
{
public  virtual  string id { get;set; }
public  virtual  string type { get;set; }
public  virtual  string value { get;set; }
public  virtual  string annotation { get;set; }
public  virtual  string permission { get;set; }
};
public partial class XsLangVisitor{
public  virtual  string ProcessFunctionSupport( FunctionSupportStatementContext[] items )
{
var obj = "";
var content = "";
var lazy = (new Lst<string>());
foreach (var item in items){
if ( (item.GetChild(0) is UsingStatementContext) ) {
lazy.add("}");
content+=(new System.Text.StringBuilder("using (").Append(((string)(Visit(item)))).Append(") ").Append(BlockLeft).Append(" ").Append(Wrap).Append("")).to_Str();
}
else {
content+=Visit(item);
}
} ;
if ( lazy.Count>0 ) {
foreach (var i in Range(lazy.Count-1,0,1,false,true)){
content+=BlockRight;
} ;
}
obj+=content;
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitFunctionStatement( FunctionStatementContext context )
{
var id = ((Result)(Visit(context.id())));
var obj = "";
if ( context.t.Type==Right_Flow ) {
var pout = ((string)(Visit(context.parameterClauseOut())));
if ( pout!="void" ) {
pout=(new System.Text.StringBuilder("").Append(Task).Append("<").Append(pout).Append(">")).to_Str();
}
else {
pout=Task;
}
obj+=(new System.Text.StringBuilder(" async ").Append(pout).Append(" ").Append(id.text).Append("")).to_Str();
}
else {
obj+=(new System.Text.StringBuilder("").Append(Visit(context.parameterClauseOut())).Append(" ").Append(id.text).Append("")).to_Str();
}
var templateContract = "";
if ( context.templateDefine()!=null ) {
var template = ((TemplateItem)(Visit(context.templateDefine())));
obj+=template.Template;
templateContract=template.Contract;
}
obj+=(new System.Text.StringBuilder("").Append(Visit(context.parameterClauseIn())).Append(" ").Append(templateContract).Append(" ").Append(Wrap).Append(" ").Append(BlockLeft).Append(" ").Append(Wrap).Append("")).to_Str();
obj+=ProcessFunctionSupport(context.functionSupportStatement());
obj+=BlockRight+Wrap;
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitReturnStatement( ReturnStatementContext context )
{
var r = ((Result)(Visit(context.tuple())));
if ( r.text=="()" ) {
r.text="";
}
return ((new System.Text.StringBuilder("return ").Append(r.text).Append(" ").Append(Terminate).Append(" ").Append(Wrap).Append("")).to_Str()) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTuple( TupleContext context )
{
var obj = "(";
foreach (var i in Range(0,context.expression().Length,1,true,false)){
var r = ((Result)(Visit(context.expression(i))));
if ( i==0 ) {
obj+=r.text;
}
else {
obj+=(new System.Text.StringBuilder(", ").Append(r.text).Append("")).to_Str();
}
} ;
obj+=")";
var result = (new Result(){data = "var",text = obj});
return (result) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTupleExpression( TupleExpressionContext context )
{
var obj = "(";
foreach (var i in Range(0,context.expression().Length,1,true,false)){
var r = ((Result)(Visit(context.expression(i))));
if ( i==0 ) {
obj+=r.text;
}
else {
obj+=(new System.Text.StringBuilder(", ").Append(r.text).Append("")).to_Str();
}
} ;
obj+=")";
var result = (new Result(){data = "var",text = obj});
return (result) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitParameterClauseIn( ParameterClauseInContext context )
{
var obj = "(";
var temp = (new Lst<string>());
foreach (var i in Range(context.parameter().Length-1,0,1,false,true)){
var p = ((Parameter)(Visit(context.parameter(i))));
temp.add((new System.Text.StringBuilder("").Append(p.annotation).Append(" ").Append(p.type).Append(" ").Append(p.id).Append(" ").Append(p.value).Append("")).to_Str());
} ;
foreach (var i in Range(temp.Count-1,0,1,false,true)){
if ( i==temp.Count-1 ) {
obj+=temp[i];
}
else {
obj+=(new System.Text.StringBuilder(", ").Append(temp[i]).Append("")).to_Str();
}
} ;
obj+=")";
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitParameterClauseOut( ParameterClauseOutContext context )
{
var obj = "";
if ( context.parameter().Length==0 ) {
obj+="void";
}
else if ( context.parameter().Length==1 ) {
var p = ((Parameter)(Visit(context.parameter(0))));
obj+=p.type;
} 
if ( context.parameter().Length>1 ) {
obj+="( ";
var temp = (new Lst<string>());
foreach (var i in Range(context.parameter().Length-1,0,1,false,true)){
var p = ((Parameter)(Visit(context.parameter(i))));
temp.add((new System.Text.StringBuilder("").Append(p.annotation).Append(" ").Append(p.type).Append(" ").Append(p.id).Append(" ").Append(p.value).Append("")).to_Str());
} ;
foreach (var i in Range(temp.Count-1,0,1,false,true)){
if ( i==temp.Count-1 ) {
obj+=temp[i];
}
else {
obj+=(new System.Text.StringBuilder(", ").Append(temp[i]).Append("")).to_Str();
}
} ;
obj+=" )";
}
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitParameterClauseSelf( ParameterClauseSelfContext context )
{
var p = (new Parameter());
var id = ((Result)(Visit(context.id(0))));
p.id=id.text;
p.permission=id.permission;
p.type=((string)(Visit(context.typeType())));
if ( context.id(1)!=null ) {
p.value=((Result)(Visit(context.id(1)))).text;
}
return (p) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitParameter( ParameterContext context )
{
var p = (new Parameter());
var id = ((Result)(Visit(context.id())));
p.id=id.text;
p.permission=id.permission;
if ( context.annotationSupport()!=null ) {
p.annotation=((string)(Visit(context.annotationSupport())));
}
if ( context.expression()!=null ) {
p.value=(new System.Text.StringBuilder("=").Append(((Result)(Visit(context.expression()))).text).Append("")).to_Str();
}
p.type=((string)(Visit(context.typeType())));
return (p) ; 
}
}
}
