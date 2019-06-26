using Library;
using static Library.Lib;
using Antlr4.Runtime;
using Antlr4.Runtime.Misc;
using System;
using static Compiler.XsParser;
using static Compiler.Compiler_Static;

namespace Compiler
{
public partial class XsLangVisitor{
public  override  object VisitTypeType( TypeTypeContext context )
{
var obj = "";
obj=((string)(Visit(context.GetChild(0))));
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTypeReference( TypeReferenceContext context )
{
var obj = "ref ";
if ( context.typeNullable()!=null ) {
obj+=Visit(context.typeNullable());
}
else if ( context.typeNotNull()!=null ) {
obj+=Visit(context.typeNotNull());
} 
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTypeNullable( TypeNullableContext context )
{
var obj = "";
obj=((string)(Visit(context.typeNotNull())));
if ( (context.typeNotNull().GetChild(0) is TypeBasicContext)&&context.typeNotNull().GetChild(0).GetText()!="Any"&&context.typeNotNull().GetChild(0).GetText()!="Str" ) {
obj+="?";
}
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTypeTuple( TypeTupleContext context )
{
var obj = "";
obj+="(";
foreach (var i in Range(0,context.typeType().Length,1,true,false)){
if ( i==0 ) {
obj+=Visit(context.typeType(i));
}
else {
obj+=(new System.Text.StringBuilder(",").Append(Visit(context.typeType(i))).Append("")).to_Str();
}
} ;
obj+=")";
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitGetType( GetTypeContext context )
{
var r = (new Result(){data = "System.Type"});
if ( context.typeType()==null ) {
r.text=(new System.Text.StringBuilder("").Append(((Result)(Visit(context.expression()))).text).Append(".GetType()")).to_Str();
}
else {
r.text=(new System.Text.StringBuilder("typeof(").Append(Visit(context.typeType())).Append(")")).to_Str();
}
return (r) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTypeArray( TypeArrayContext context )
{
var obj = "";
obj+=(new System.Text.StringBuilder("").Append(Visit(context.typeType())).Append("[]")).to_Str();
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTypeList( TypeListContext context )
{
var obj = "";
obj+=(new System.Text.StringBuilder("").Append(Lst).Append("<").Append(Visit(context.typeType())).Append(">")).to_Str();
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTypeSet( TypeSetContext context )
{
var obj = "";
obj+=(new System.Text.StringBuilder("").Append(Set).Append("<").Append(Visit(context.typeType())).Append(">")).to_Str();
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTypeDictionary( TypeDictionaryContext context )
{
var obj = "";
obj+=(new System.Text.StringBuilder("").Append(Dic).Append("<").Append(Visit(context.typeType(0))).Append(",").Append(Visit(context.typeType(1))).Append(">")).to_Str();
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTypePackage( TypePackageContext context )
{
var obj = "";
obj+=Visit(context.nameSpaceItem());
if ( context.templateCall()!=null ) {
obj+=Visit(context.templateCall());
}
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTypeFunction( TypeFunctionContext context )
{
var obj = "";
var @in = ((string)(Visit(context.typeFunctionParameterClause(0))));
var @out = ((string)(Visit(context.typeFunctionParameterClause(1))));
if ( context.t.Type==Right_Arrow ) {
if ( @out.Length==0 ) {
if ( @in.Length==0 ) {
obj="Action";
}
else {
obj=(new System.Text.StringBuilder("Action<").Append(@in).Append(">")).to_Str();
}
}
else {
if ( @out.first_index_of(",")>=0 ) {
@out=(new System.Text.StringBuilder("(").Append(@out).Append(")")).to_Str();
}
if ( @in.Length==0 ) {
obj=(new System.Text.StringBuilder("Func<").Append(@out).Append(">")).to_Str();
}
else {
obj=(new System.Text.StringBuilder("Func<").Append(@in).Append(", ").Append(@out).Append(">")).to_Str();
}
}
}
else {
if ( @out.Length==0 ) {
if ( @in.Length==0 ) {
obj=(new System.Text.StringBuilder("Func<").Append(Task).Append(">")).to_Str();
}
else {
obj=(new System.Text.StringBuilder("Func<").Append(@in).Append(", ").Append(Task).Append(">")).to_Str();
}
}
else {
if ( @in.Length==0 ) {
obj=(new System.Text.StringBuilder("Func<").Append(Task).Append("<").Append(@out).Append(">>")).to_Str();
}
else {
obj=(new System.Text.StringBuilder("Func<").Append(@in).Append(", ").Append(Task).Append("<").Append(@out).Append(">>")).to_Str();
}
}
}
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTypeAny( TypeAnyContext context )
{
return (Any) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTypeFunctionParameterClause( TypeFunctionParameterClauseContext context )
{
var obj = "";
foreach (var i in Range(0,context.typeType().Length-1,1,true,true)){
var p = ((string)(Visit(context.typeType(i))));
if ( i==0 ) {
obj+=p;
}
else {
obj+=(new System.Text.StringBuilder(", ").Append(p).Append("")).to_Str();
}
} ;
return (obj) ; 
}
}
public partial class XsLangVisitor{
public  override  object VisitTypeBasic( TypeBasicContext context )
{
var obj = "";
switch (context.t.Type) {
case TypeI8 :
{ obj=I8;
} break;
case TypeU8 :
{ obj=U8;
} break;
case TypeI16 :
{ obj=I16;
} break;
case TypeU16 :
{ obj=U16;
} break;
case TypeI32 :
{ obj=I32;
} break;
case TypeU32 :
{ obj=U32;
} break;
case TypeI64 :
{ obj=I64;
} break;
case TypeU64 :
{ obj=U64;
} break;
case TypeF32 :
{ obj=F32;
} break;
case TypeF64 :
{ obj=F64;
} break;
case TypeChr :
{ obj=Chr;
} break;
case TypeStr :
{ obj=Str;
} break;
case TypeBool :
{ obj=Bool;
} break;
case TypeInt :
{ obj=Int;
} break;
case TypeNum :
{ obj=Num;
} break;
case TypeByte :
{ obj=U8;
} break;
default:{
obj=Any;
}break;
} 
return (obj) ; 
}
}
}
