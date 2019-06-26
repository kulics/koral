using Library;
using static Library.Lib;
using Antlr4.Runtime;
using System;
using System.IO;
using System.Text;

namespace Compiler
{
public partial class Compiler_Static{
protected static string _Read_Path { get;set; }
protected static string _Path_Line { get;set; }
public static void Main( string[] args )
{
var os = Environment.OSVersion.Platform;
if ( os==PlatformID.Unix||os==PlatformID.MacOSX ) {
_Read_Path="./";
_Path_Line="/";
}
else {
_Read_Path=".\\";
_Path_Line="\\";
}
Compiled(_Read_Path);
Prt("Completed");
Rd();
}
public static void Compiled( string path )
{
var Files = Directory.GetFiles(path, "*.xs");
foreach (var file in Files){
using (var fs_read = (new FileStream(file, FileMode.Open))) { 
try {
var FSLength = ((int)(fs_read.Length));
var Byte_Block = Array<byte>(FSLength);
var r = fs_read.Read(Byte_Block, 0, Byte_Block.Length);
var Input = Encoding.UTF8.GetString(Byte_Block);
Input.Replace("\r", "");
var Stream = (new AntlrInputStream(Input));
var Lexer = (new XsLexer(Stream));
var Tokens = (new CommonTokenStream(Lexer));
var Parser = (new XsParser(Tokens));
Parser.BuildParseTree=true;
Parser.RemoveErrorListeners();
Parser.AddErrorListener((new ErrorListener(){File_Dir = file}));
var AST = Parser.program();
var Visitor = (new XsLangVisitor());
var Result = Visitor.Visit(AST);
var Byte_Result = Encoding.UTF8.GetBytes(Result.to_Str());
using (var fs_write = (new FileStream(_Read_Path+file.sub_Str(0, file.Length-3)+".cs", FileMode.Create))) { 
fs_write.Write(Byte_Result, 0, Byte_Result.Length);
}}
catch( Exception err )
{
Prt(err);
return  ; 
}
}} ;
var Folders = Directory.GetDirectories(path);
foreach (var folder in Folders){
Compiled(folder);
} ;
}
}
}
