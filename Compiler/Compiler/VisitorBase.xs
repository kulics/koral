"Compiler" {
    "Antlr4/Runtime"
    "Antlr4/Runtime/Misc"
    "System"

    "Compiler" XsParser.
    "Compiler" Compiler Static.
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

BlockLeft :: "{"
BlockRight :: "}"

Task :: "System.Threading.Tasks.Task"

Result -> {
    data(): Any
    text(): Str
    permission(): Str
    isVirtual(): Bool
}

XsLangVisitor -> {
    :XsParserBaseVisitor<Any> 

    self ID := ""
    super ID := ""
}
(me:XsLangVisitor)(base) VisitProgram(context: ProgramContext) -> (v: Any) {
    Statement List := context.statement()
    Result := ""
    Statement List @ item {
        Result += VisitStatement(item)
    }
    <- (Result)
}

(me:XsLangVisitor)(base) VisitId(context: IdContext) -> (v: Any) {
    r := Result{data = "var"}
    first := Visit(context.GetChild(0)):(Result)
    r.permission = first.permission
    r.text = first.text
    r.isVirtual = first.isVirtual
    ? context.ChildCount >= 2 {
        [1 < context.ChildCount] @ i {
            other := Visit(context.GetChild(i)):(Result)
            r.text += "_"other.text""
        }
    }

    ? keywords.Exists({t -> t == r.text}) {
        r.text = "@"r.text""
    }
    ? r.text == self ID {
        r.text = "this"
    } r.text == super ID {
        r.text = "base"
    }
    <- (r)
}

(me:XsLangVisitor)(base) VisitIdItem(context: IdItemContext) -> (v: Any) {
    r := Result{data = "var"}
    ? context.typeBasic() >< Nil {
        r.permission = "public"
        r.text += context.typeBasic().GetText()
        r.isVirtual = True
    } context.typeAny() >< Nil {
        r.permission = "public"
        r.text += context.typeAny().GetText()
        r.isVirtual = True
    } context.linqKeyword() >< Nil {
        r.permission = "public"
        r.text += Visit(context.linqKeyword())
        r.isVirtual = True
    } context.op.Type == IDPublic {
        r.permission = "public"
        r.text += context.op.Text
        r.isVirtual = True
    } context.op.Type == IDPrivate {
        r.permission = "protected"
        r.text += context.op.Text
        r.isVirtual = True
    }
    <- (r)
}

(me:XsLangVisitor)(base) VisitBoolExpr(context: BoolExprContext) -> (v: Any) {
    r := Result{}
    ? context.t.Type == TrueLiteral {
        r.data = Bool
        r.text = T
    } context.t.Type == FalseLiteral {
        r.data = Bool
        r.text = F
    }
    <- (r)
}

(me:XsLangVisitor)(base) VisitAnnotationSupport(context: AnnotationSupportContext) -> (v: Any) {
    <- (Visit(context.annotation()):(Str))
}

(me:XsLangVisitor)(base) VisitAnnotation(context: AnnotationContext) -> (v: Any) {
    obj := ""
    id := ""
    ? context.id() >< Nil {
        id = ""Visit(context.id()):(Result).text":"
    }

    r := Visit(context.annotationList()):(Str)
    obj += "[" id "" r "]"
    <- (obj)
}

(me:XsLangVisitor)(base) VisitAnnotationList(context: AnnotationListContext) -> (v: Any) {
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

(me:XsLangVisitor)(base) VisitAnnotationItem(context: AnnotationItemContext) -> (v: Any) {
    obj := ""
    obj += Visit(context.id()):(Result).text
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

(me:XsLangVisitor)(base) VisitAnnotationAssign(context: AnnotationAssignContext) -> (v: Any) {
    obj := ""
    id := ""
    ? context.id() >< Nil {
        id = "" Visit(context.id()):(Result).text "="
    }
    r := Visit(context.expression()):(Result)
    obj = id + r.text
    <- (obj)
}
