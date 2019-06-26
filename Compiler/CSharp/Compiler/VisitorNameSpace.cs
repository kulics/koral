using Library;
using static Library.Lib;
using Antlr4.Runtime;
using Antlr4.Runtime.Misc;
using System;
using static Compiler.XsParser;
using static Compiler.Compiler_Static;

namespace Compiler
{
public partial class Namespace
{
public  virtual  string name { get;set; }
public  virtual  string imports { get;set; }
};
public partial class XsLangVisitor{
public  override  object VisitStatement( StatementContext context )
{
var obj = "";
var ns = ((Namespace)(Visit(context.exportStatement())));
obj+=(new System.Text.StringBuilder("using Library;").Append(Wrap).Append("using static Library.Lib;").Append(Wrap).Append("")).to_Str();
obj+=ns.imports+Wrap;
if ( context.annotationSupport()!=null ) {
obj+=Visit(context.annotationSupport());
}
obj+=(new System.Text.StringBuilder("namespace ").Append(ns.name+Wrap+BlockLeft+Wrap).Append("")).to_Str();
var content = "";
var contentStatic = "";
foreach (var item in context.namespaceSupportStatement()){
var type = item.GetChild(0).GetType();
if ( type==typeof(NamespaceVariableStatementContext)||type==typeof(NamespaceControlStatementContext)||type==typeof(NamespaceFunctionStatementContext)||type==typeof(NamespaceConstantStatementContext) ) {
contentStatic+=Visit(item);
}
else {
content+=Visit(item);
}
} ;
obj+=content;
if ( contentStatic!="" ) {
obj+=(new System.Text.StringBuilder("public partial class ").Append(ns.name.sub_Str(ns.name.last_index_of(".")+1)).Append("_Static")).to_Str()+BlockLeft+Wrap+contentStatic+BlockRight+Wrap;
}
obj+=BlockRight+Wrap;
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitExportStatement( ExportStatementContext context )
{
var name = context.TextLiteral().GetText();
name=name.sub_Str(1, name.len()-2);
name=name.replace("/", ".");
var obj = (new Namespace(){name = name});
foreach (var item in context.importStatement()){
obj.imports+=((string)(Visit(item)));
} ;
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitImportStatement( ImportStatementContext context )
{
var obj = "";
if ( context.annotationSupport()!=null ) {
obj+=Visit(context.annotationSupport());
}
var ns = context.TextLiteral().GetText();
ns=ns.sub_Str(1, ns.len()-2);
ns=ns.replace("/", ".");
if ( context.call()!=null ) {
obj+="using static "+ns+"."+((Result)(Visit(context.id()))).text;
}
else if ( context.id()!=null ) {
obj+="using "+ns+"."+((Result)(Visit(context.id()))).text;
} 
else {
obj+="using "+ns;
}
obj+=Terminate+Wrap;
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitNameSpaceItem( NameSpaceItemContext context )
{
var obj = "";
foreach (var i in Range(0,context.id().Length,1,true,false)){
var id = ((Result)(Visit(context.id(i))));
if ( i==0 ) {
obj+=""+id.text;
}
else {
obj+="."+id.text;
}
} ;
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitName( NameContext context )
{
var obj = "";
foreach (var i in Range(0,context.id().Length,1,true,false)){
var id = ((Result)(Visit(context.id(i))));
if ( i==0 ) {
obj+=""+id.text;
}
else {
obj+="."+id.text;
}
} ;
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitEnumStatement( EnumStatementContext context )
{
var obj = "";
var id = ((Result)(Visit(context.id())));
var header = "";
var typ = ((string)(Visit(context.typeType())));
if ( context.annotationSupport()!=null ) {
header+=Visit(context.annotationSupport());
}
header+=id.permission+" enum "+id.text+":"+typ;
header+=Wrap+BlockLeft+Wrap;
foreach (var i in Range(0,context.enumSupportStatement().Length,1,true,false)){
obj+=Visit(context.enumSupportStatement(i));
} ;
obj+=BlockRight+Terminate+Wrap;
obj=header+obj;
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitEnumSupportStatement( EnumSupportStatementContext context )
{
var id = ((Result)(Visit(context.id())));
if ( context.integerExpr()!=null ) {
var op = "";
if ( context.add()!=null ) {
op=((string)(Visit(context.add())));
}
id.text+=" = "+op+Visit(context.integerExpr());
}
return (id.text+",") ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitNamespaceFunctionStatement( NamespaceFunctionStatementContext context )
{
var id = ((Result)(Visit(context.id())));
var obj = "";
if ( context.annotationSupport()!=null ) {
obj+=Visit(context.annotationSupport());
}
if ( context.t.Type==Right_Flow ) {
var pout = ((string)(Visit(context.parameterClauseOut())));
if ( pout!="void" ) {
pout=(new System.Text.StringBuilder("").Append(Task).Append("<").Append(pout).Append(">")).to_Str();
}
else {
pout=Task;
}
obj+=(new System.Text.StringBuilder("").Append(id.permission).Append(" async static ").Append(pout).Append(" ").Append(id.text).Append("")).to_Str();
}
else {
obj+=(new System.Text.StringBuilder("").Append(id.permission).Append(" static ").Append(Visit(context.parameterClauseOut())).Append(" ").Append(id.text).Append("")).to_Str();
}
var templateContract = "";
if ( context.templateDefine()!=null ) {
var template = ((TemplateItem)(Visit(context.templateDefine())));
obj+=template.Template;
templateContract=template.Contract;
}
obj+=Visit(context.parameterClauseIn())+templateContract+Wrap+BlockLeft+Wrap;
obj+=ProcessFunctionSupport(context.functionSupportStatement());
obj+=BlockRight+Wrap;
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitNamespaceConstantStatement( NamespaceConstantStatementContext context )
{
var id = ((Result)(Visit(context.id())));
var expr = ((Result)(Visit(context.expression())));
var typ = "";
if ( context.typeType()!=null ) {
typ=((string)(Visit(context.typeType())));
}
else {
typ=((string)(expr.data));
}
var obj = "";
if ( context.annotationSupport()!=null ) {
obj+=Visit(context.annotationSupport());
}
switch (typ) {
case I8 :
{ typ="ubyte";
} break;
case I16 :
{ typ="short";
} break;
case I32 :
{ typ="int";
} break;
case I64 :
{ typ="long";
} break;
case U8 :
{ typ="byte";
} break;
case U16 :
{ typ="ushort";
} break;
case U32 :
{ typ="uint";
} break;
case U64 :
{ typ="ulong";
} break;
case F32 :
{ typ="float";
} break;
case F64 :
{ typ="double";
} break;
case Chr :
{ typ="char";
} break;
case Str :
{ typ="string";
} break;
} 
obj+=(new System.Text.StringBuilder("").Append(id.permission).Append(" const ").Append(typ).Append(" ").Append(id.text).Append(" = ").Append(expr.text).Append(" ").Append(Terminate+Wrap).Append("")).to_Str();
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitNamespaceVariableStatement( NamespaceVariableStatementContext context )
{
var r1 = ((Result)(Visit(context.id())));
var isMutable = r1.isVirtual;
var typ = "";
Result r2 = null;
if ( context.expression()!=null ) {
r2=((Result)(Visit(context.expression())));
typ=((string)(r2.data));
}
if ( context.typeType()!=null ) {
typ=((string)(Visit(context.typeType())));
}
var obj = "";
if ( context.annotationSupport()!=null ) {
obj+=Visit(context.annotationSupport());
}
obj+=(new System.Text.StringBuilder("").Append(r1.permission).Append(" static ").Append(typ).Append(" ").Append(r1.text).Append("")).to_Str();
if ( r2!=null ) {
obj+=(new System.Text.StringBuilder(" = ").Append(r2.text).Append(" ").Append(Terminate+Wrap).Append("")).to_Str();
}
else {
obj+=Terminate+Wrap;
}
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitNamespaceControlStatement( NamespaceControlStatementContext context )
{
var r1 = ((Result)(Visit(context.id())));
var isMutable = r1.isVirtual;
var typ = "";
Result r2 = null;
if ( context.expression()!=null ) {
r2=((Result)(Visit(context.expression())));
typ=((string)(r2.data));
}
if ( context.typeType()!=null ) {
typ=((string)(Visit(context.typeType())));
}
var obj = "";
if ( context.annotationSupport()!=null ) {
obj+=Visit(context.annotationSupport());
}
if ( context.packageControlSubStatement().Length>0 ) {
obj+=(new System.Text.StringBuilder("").Append(r1.permission).Append(" static ").Append(typ).Append(" ").Append(r1.text+BlockLeft).Append("")).to_Str();
var record = (new Dic<string,bool>());
foreach (var item in context.packageControlSubStatement()){
var temp = ((Result)(Visit(item)));
obj+=temp.text;
record[((string)(temp.data))]=true;
} ;
if ( r2!=null ) {
obj=(new System.Text.StringBuilder("protected static ").Append(typ).Append(" _").Append(r1.text).Append(" = ").Append(r2.text).Append("; ").Append(Wrap).Append("")).to_Str()+obj;
if ( !record.ContainsKey("get") ) {
obj+=(new System.Text.StringBuilder("get { return _").Append(r1.text).Append("; }")).to_Str();
}
if ( isMutable&&!record.ContainsKey("set") ) {
obj+=(new System.Text.StringBuilder("set { _").Append(r1.text).Append(" = value; }")).to_Str();
}
}
obj+=BlockRight+Wrap;
}
else {
if ( isMutable ) {
obj+=(new System.Text.StringBuilder("").Append(r1.permission).Append(" static ").Append(typ).Append(" ").Append(r1.text).Append(" { get;set; }")).to_Str();
if ( r2!=null ) {
obj+=(new System.Text.StringBuilder(" = ").Append(r2.text).Append(" ").Append(Terminate+Wrap).Append("")).to_Str();
}
else {
obj+=Wrap;
}
}
else {
obj+=(new System.Text.StringBuilder("").Append(r1.permission).Append(" static ").Append(typ).Append(" ").Append(r1.text).Append(" { get; }")).to_Str();
if ( r2!=null ) {
obj+=(new System.Text.StringBuilder(" = ").Append(r2.text).Append(" ").Append(Terminate+Wrap).Append("")).to_Str();
}
else {
obj+=Wrap;
}
}
}
return (obj) ; 
}
}
public partial class Compiler_Static{
public static (  string id ,  string type  ) GetControlSub( string id )
{
var typ = "";
switch (id) {
case "get" :
{ id=" get ";
typ="get";
} break;
case "set" :
{ id=" set ";
typ="set";
} break;
case "_get" :
{ id=" protected get ";
typ="get";
} break;
case "_set" :
{ id=" protected set ";
typ="set";
} break;
case "add" :
{ id=" add ";
typ="add";
} break;
case "remove" :
{ id=" remove ";
typ="remove";
} break;
} 
return (id, typ) ; 
}
}
}
