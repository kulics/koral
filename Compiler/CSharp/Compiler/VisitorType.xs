"Compiler" {
    "Antlr4/Runtime"
    "Antlr4/Runtime/Misc"
    "System"

    "Compiler" XsParser.
    "Compiler" Compiler Static.
}

(me:XsLangVisitor)(base) VisitTypeType(context: TypeTypeContext) -> (v: Any) {
    obj := ""
    obj = Visit(context.GetChild(0)):(Str)
    <- (obj)
}

(me:XsLangVisitor)(base) VisitTypeReference(context: TypeReferenceContext) -> (v: Any) {
    obj := "ref "
    ? context.typeNullable() >< Nil {
        obj += Visit(context.typeNullable())
    } context.typeNotNull() >< Nil {
        obj += Visit(context.typeNotNull())
    }
    <- (obj)
}

(me:XsLangVisitor)(base) VisitTypeNullable(context: TypeNullableContext) -> (v: Any) {
    obj := ""
    obj = Visit(context.typeNotNull()):(Str)
    ? context.typeNotNull().GetChild(0) == :TypeBasicContext &
        context.typeNotNull().GetChild(0).GetText() >< "Any" &
        context.typeNotNull().GetChild(0).GetText() >< "Str" {
        obj += "?"
    }
    <- (obj)
}

(me:XsLangVisitor)(base) VisitTypeTuple(context: TypeTupleContext) -> (v: Any) {
    obj := ""
    obj += "("
    [0 < context.typeType().Length] @ i {
        ? i == 0 {
            obj += Visit(context.typeType(i))
        } _ {
            obj += ","Visit(context.typeType(i))""
        }
    }
    obj += ")"
    <- (obj)
}

(me:XsLangVisitor)(base) VisitGetType(context: GetTypeContext) -> (v: Any) {
    r := Result{data = "System.Type"}
    ? context.typeType() == Nil {
        r.text = ""Visit(context.expression()):(Result).text".GetType()"
    } _ {
        r.text = "typeof("Visit(context.typeType())")"
    }
    <- (r)
}

(me:XsLangVisitor)(base) VisitTypeArray(context: TypeArrayContext) -> (v: Any) {
    obj := ""
    obj += ""Visit(context.typeType())"[]"
    <- (obj)
}

(me:XsLangVisitor)(base) VisitTypeList(context: TypeListContext) -> (v: Any) {
    obj := ""
    obj += ""Lst"<"Visit(context.typeType())">"
    <- (obj)
}

(me:XsLangVisitor)(base) VisitTypeSet(context: TypeSetContext) -> (v: Any) {
    obj := ""
    obj += ""Set"<"Visit(context.typeType())">"
    <- (obj)
}

(me:XsLangVisitor)(base) VisitTypeDictionary(context: TypeDictionaryContext) -> (v: Any) {
    obj := ""
    obj += ""Dic"<"Visit(context.typeType(0))","Visit(context.typeType(1))">"
    <- (obj)
}

(me:XsLangVisitor)(base) VisitTypePackage(context: TypePackageContext) -> (v: Any) {
    obj := ""
    obj += Visit(context.nameSpaceItem())
    ? context.templateCall() >< Nil {
        obj += Visit(context.templateCall())
    }
    <- (obj)
}

(me:XsLangVisitor)(base) VisitTypeFunction(context: TypeFunctionContext) -> (v: Any) {
    obj := ""
    in := Visit(context.typeFunctionParameterClause(0)):(Str)
    out := Visit(context.typeFunctionParameterClause(1)):(Str)
    ? context.t.Type == Right Arrow {
        ? out.Length == 0 {
            ? in.Length == 0 {
                obj = "Action"
            } _ {
                obj = "Action<"in">"
            }
        } _ {
            ? out.first index of(",") >= 0 {
                out = "(" out ")"
            }
            ? in.Length == 0 {
                obj = "Func<"out">"
            } _ {
                obj = "Func<"in", "out">"
            }
        }
    } _ {
        ? out.Length == 0 {
            ? in.Length == 0 {
                obj = "Func<"Task">"
            } _ {
                obj = "Func<"in", "Task">"
            }
        } _ {
            ? in.Length == 0 {
                obj = "Func<"Task"<"out">>";
            } _ {
                obj = "Func<"in", "Task"<"out">>"
            }
        }
    }
    <- (obj)
}

(me:XsLangVisitor)(base) VisitTypeAny(context: TypeAnyContext) -> (v: Any) {
    <- (Any)
}

(me:XsLangVisitor)(base) VisitTypeFunctionParameterClause(context: TypeFunctionParameterClauseContext) -> (v: Any) {
    obj := ""
    [0 <= context.typeType().Length - 1] @ i {
        p := Visit(context.typeType(i)):(Str)
        ? i == 0 {
            obj += p
        } _ {
            obj += ", "p""
        }
    }
    <- (obj)
}

(me:XsLangVisitor)(base) VisitTypeBasic(context: TypeBasicContext) -> (v: Any) {
    obj := ""
    context.t.Type ? TypeI8 {
        obj = I8
    } TypeU8 {
        obj = U8
    } TypeI16 {
        obj = I16
    } TypeU16 {
        obj = U16
    } TypeI32 {
        obj = I32
    } TypeU32 {
        obj = U32
    } TypeI64 {
        obj = I64
    } TypeU64 {
        obj = U64
    } TypeF32 {
        obj = F32
    } TypeF64 {
        obj = F64
    } TypeChr {
        obj = Chr
    } TypeStr {
        obj = Str
    } TypeBool {
        obj = Bool
    } TypeInt {
        obj = Int
    } TypeNum {
        obj = Num
    } TypeByte {
        obj = U8
    } _ {
        obj = Any
    }
    <- (obj)
}
