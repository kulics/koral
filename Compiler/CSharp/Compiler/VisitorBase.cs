using Library;
using static Library.Lib;
using Antlr4.Runtime;
using Antlr4.Runtime.Misc;
using System;
using static Compiler.XsParser;
using static Compiler.Compiler_Static;

namespace Compiler
{
public partial class Result
{
public  virtual  object data { get;set; }
public  virtual  string text { get;set; }
public  virtual  string permission { get;set; }
public  virtual  bool isVirtual { get;set; }
};
public partial class XsLangVisitor:XsParserBaseVisitor<object>
{
public string self_ID = "" ; 
public string super_ID = "" ; 
};
public partial class XsLangVisitor{
public  override  object VisitProgram( ProgramContext context )
{
var Statement_List = context.statement();
var Result = "";
foreach (var item in Statement_List){
Result+=VisitStatement(item);
} ;
return (Result) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitId( IdContext context )
{
var r = (new Result(){data = "var"});
var first = ((Result)(Visit(context.GetChild(0))));
r.permission=first.permission;
r.text=first.text;
r.isVirtual=first.isVirtual;
if ( context.ChildCount>=2 ) {
foreach (var i in Range(1,context.ChildCount,1,true,false)){
var other = ((Result)(Visit(context.GetChild(i))));
r.text+=(new System.Text.StringBuilder("_").Append(other.text).Append("")).to_Str();
} ;
}
if ( keywords.Exists((t)=>t==r.text) ) {
r.text=(new System.Text.StringBuilder("@").Append(r.text).Append("")).to_Str();
}
if ( r.text==self_ID ) {
r.text="this";
}
else if ( r.text==super_ID ) {
r.text="base";
} 
return (r) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitIdItem( IdItemContext context )
{
var r = (new Result(){data = "var"});
if ( context.typeBasic()!=null ) {
r.permission="public";
r.text+=context.typeBasic().GetText();
r.isVirtual=true;
}
else if ( context.typeAny()!=null ) {
r.permission="public";
r.text+=context.typeAny().GetText();
r.isVirtual=true;
} 
else if ( context.linqKeyword()!=null ) {
r.permission="public";
r.text+=Visit(context.linqKeyword());
r.isVirtual=true;
} 
else if ( context.op.Type==IDPublic ) {
r.permission="public";
r.text+=context.op.Text;
r.isVirtual=true;
} 
else if ( context.op.Type==IDPrivate ) {
r.permission="protected";
r.text+=context.op.Text;
r.isVirtual=true;
} 
return (r) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitBoolExpr( BoolExprContext context )
{
var r = (new Result());
if ( context.t.Type==TrueLiteral ) {
r.data=Bool;
r.text=T;
}
else if ( context.t.Type==FalseLiteral ) {
r.data=Bool;
r.text=F;
} 
return (r) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitAnnotationSupport( AnnotationSupportContext context )
{
return (((string)(Visit(context.annotation())))) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitAnnotation( AnnotationContext context )
{
var obj = "";
var id = "";
if ( context.id()!=null ) {
id=(new System.Text.StringBuilder("").Append(((Result)(Visit(context.id()))).text).Append(":")).to_Str();
}
var r = ((string)(Visit(context.annotationList())));
obj+=(new System.Text.StringBuilder("[").Append(id).Append("").Append(r).Append("]")).to_Str();
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitAnnotationList( AnnotationListContext context )
{
var obj = "";
foreach (var i in Range(0,context.annotationItem().Length,1,true,false)){
if ( i>0 ) {
obj+=(new System.Text.StringBuilder(",").Append(Visit(context.annotationItem(i))).Append("")).to_Str();
}
else {
obj+=Visit(context.annotationItem(i));
}
} ;
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitAnnotationItem( AnnotationItemContext context )
{
var obj = "";
obj+=((Result)(Visit(context.id()))).text;
foreach (var i in Range(0,context.annotationAssign().Length,1,true,false)){
if ( i>0 ) {
obj+=(new System.Text.StringBuilder(",").Append(Visit(context.annotationAssign(i))).Append("")).to_Str();
}
else {
obj+=(new System.Text.StringBuilder("(").Append(Visit(context.annotationAssign(i))).Append("")).to_Str();
}
} ;
if ( context.annotationAssign().Length>0 ) {
obj+=")";
}
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitAnnotationAssign( AnnotationAssignContext context )
{
var obj = "";
var id = "";
if ( context.id()!=null ) {
id=(new System.Text.StringBuilder("").Append(((Result)(Visit(context.id()))).text).Append("=")).to_Str();
}
var r = ((Result)(Visit(context.expression())));
obj=id+r.text;
return (obj) ; 
}
}
public partial class Compiler_Static{
public const string Terminate = ";" ;
public const string Wrap = "\r\n" ;
public const string Any = "object" ;
public const string Int = "int" ;
public const string Num = "double" ;
public const string I8 = "sbyte" ;
public const string I16 = "short" ;
public const string I32 = "int" ;
public const string I64 = "long" ;
public const string U8 = "byte" ;
public const string U16 = "ushort" ;
public const string U32 = "uint" ;
public const string U64 = "ulong" ;
public const string F32 = "float" ;
public const string F64 = "double" ;
public const string Bool = "bool" ;
public const string T = "true" ;
public const string F = "false" ;
public const string Chr = "char" ;
public const string Str = "string" ;
public const string Lst = "Lst" ;
public const string Set = "Set" ;
public const string Dic = "Dic" ;
public const string BlockLeft = "{" ;
public const string BlockRight = "}" ;
public const string Task = "System.Threading.Tasks.Task" ;
}
}
