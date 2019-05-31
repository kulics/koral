\Compiler <- {
    Antlr4\Runtime
    Antlr4\Runtime\Misc
    System
    Library
    Compiler.XsParser
    Compiler.Compiler Static
}

ErrorListener -> {
    File Dir(): Str
} ...BaseErrorListener {
    SyntaxError(recognizer: IRecognizer, offendingSymbol: ?IToken, 
    line: Int, charPositionInLine: Int, msg: Int, 
    e: ?RecognitionException) -> () {
        ...SyntaxError(recognizer, offendingSymbol, line, charPositionInLine, msg, e)
        Prt("------Syntax Error------")
        Prt("File: "File Dir"")
        Prt("Line: "line"  Column: "charPositionInLine"")
        Prt("OffendingSymbol: "offendingSymbol.Text"")
        Prt("Message: "msg"")
    }
}

Terminate :: ";"
Wrap :: "\r\n"

Any :: "object"
Int :: "int"
Num :: "double"
I8 :: "sbyte"
I16 :: "short"
I32 :: "int"
I64 :: "long"

U8 :: "byte"
U16 :: "ushort"
U32 :: "uint"
U64 :: "ulong"

F32 :: "float"
F64 :: "double"

Bool :: "bool"
T :: "true"
F :: "false"

Chr :: "char"
Str :: "string"
Lst :: "Lst"
Set :: "Set"
Dic :: "Dic"

BlockLeft = "{"
BlockRight = "}"

Task = "System.Threading.Tasks.Task";

Result -> {
    data(): {}
    text(): Str
    permission(): Str
    isVirtual(): Bool
}

XsVisitor -> {
} ...XsBaseVisitor<{}>  {
    VisitProgram(context: ProgramContext) -> (v: {}) {
        Statement List := context.statement()
        Result := ""
        Statement List @ item {
            Result += VisitStatement(item)
        }
        <- (Result)
    }

    VisitId(context: IdContext) -> (v: {}) {
        r := Result{data = "var"}
        first := Visit(context.GetChild(0)):Result
        r.permission = first.permission
        r.text = first.text
        r.isVirtual = first.isVirtual
        ? context.ChildCount >= 2 {
            [1 < context.ChildCount] @ i {
                other := Visit(context.GetChild(i)):Result
                r.text += "_"other.text""
            }
        }

        ? keywords.Exists({t -> t == r.text}) {
            r.text = "@"r.text""
        }
        <- (r)
    }

    VisitIdItem(context: IdItemContext) -> (v: {}) {
        r := Result{data = "var"}
        ? context.typeBasic() >< () {
            r.permission = "public"
            r.text += context.typeBasic().GetText()
        } context.linqKeyword() >< () {
            r.permission = "public"
            r.text += Visit(context.linqKeyword())
        } context.op.Type == IDPublic {
            r.permission = "public"
            r.text += context.op.Text
            r.isVirtual = r.text[0].is Upper()
        } context.op.Type == IDPrivate) {
            r.permission = "protected"
            r.text += context.op.Text
            r.isVirtual = r.text[r.text.find first({it -> it >< '_'})].is Upper()
        }
        <- (r)
    }

    VisitBool(context: BoolContext) -> (v: {}) {
        r := Result{}
        ? context.t.Type == True {
            r.data = Bool
            r.text = T
        } context.t.Type == False {
            r.data = Bool
            r.text = F
        }
        <- (r)
    }

    VisitAnnotationSupport(context: AnnotationSupportContext) -> (v: {}) {
        <- (Visit(context.annotation()):Str)
    }

    VisitAnnotation(context: AnnotationContext) -> (v: {}) {
        obj := ""
        id := ""
        ? context.id() >< () {
            id = ""Visit(context.id()):Result.text":"
        }

        r := Visit(context.annotationList()):Str
        obj += "[" id "" r "]"
        <- (obj)
    }

    VisitAnnotationList(context: AnnotationListContext) -> (v: {}) {
        obj := ""
        [0 < context.annotationItem().Length] @ i {
            ? i > 0 {
                obj += "," Visit(context.annotationItem(i)) ""
            } _ {
                obj += Visit(context.annotationItem(i))
            }
        }
        <- (obj)
    }

    VisitAnnotationItem(context: AnnotationItemContext) -> (v: {}) {
        obj := ""
        obj += Visit(context.id():Result.text
        [0 < context.annotationAssign().Length] @ i {
            ? i > 0 {
                obj += "," Visit(context.annotationAssign(i)) ""
            } _ {
                obj += "(" Visit(context.annotationAssign(i)) ""
            }
        }
        ? context.annotationAssign().Length > 0 {
            obj += ")"
        }
        <- (obj)
    }

    VisitAnnotationAssign(context: AnnotationAssignContext) -> (v: {}) {
        obj := ""
        id := ""
        ? context.id() >< () {
            id = "" Visit(context.id():Result.text "="
        }
        r := Visit(context.expression()):Result
        obj = id + r.text
        <- (obj)
    }
}
