using Library;
using static Library.Lib;
using Antlr4.Runtime;
using Antlr4.Runtime.Misc;
using System;
using static Compiler.XsParser;
using static Compiler.Compiler_Static;

namespace Compiler
{
public partial class ErrorListener:BaseErrorListener
{
public  virtual  string File_Dir { get;set; }
};
public partial class ErrorListener{
public  override  void SyntaxError( IRecognizer recognizer ,  IToken offendingSymbol ,  int line ,  int charPositionInLine ,  string msg ,  RecognitionException e )
{
base.SyntaxError(recognizer, offendingSymbol, line, charPositionInLine, msg, e);
Prt("------Syntax Error------");
Prt((new System.Text.StringBuilder("File: ").Append(this.File_Dir).Append("")).to_Str());
Prt((new System.Text.StringBuilder("Line: ").Append(line).Append("  Column: ").Append(charPositionInLine).Append("")).to_Str());
Prt((new System.Text.StringBuilder("OffendingSymbol: ").Append(offendingSymbol.Text).Append("")).to_Str());
Prt((new System.Text.StringBuilder("Message: ").Append(msg).Append("")).to_Str());
}
}
}
