"Compiler" {
    "Antlr4/Runtime"
    "Antlr4/Runtime/Misc"
    "System"

    "Compiler" XsParser.
    "Compiler" Compiler Static.
}

ErrorListener -> {
    BaseErrorListener
    File Dir(): Str
} 
(me:ErrorListener)(super) SyntaxError(recognizer: IRecognizer, offendingSymbol: ?IToken, 
    line: Int, charPositionInLine: Int, msg: Str, 
    e: ?RecognitionException) -> () {
        super.SyntaxError(recognizer, offendingSymbol, line, charPositionInLine, msg, e)
        Prt("------Syntax Error------")
        Prt("File: "me.File Dir"")
        Prt("Line: "line"  Column: "charPositionInLine"")
        Prt("OffendingSymbol: "offendingSymbol.Text"")
        Prt("Message: "msg"")
    }
}