\Compiler <- {
    Antlr4\Runtime
    Antlr4\Runtime\Misc
    System

    Compiler.XsParser
    Compiler.Compiler Static
}

XsLangVisitor -> {
} ...XsParserBaseVisitor<{}> {
    VisitTypeType(context: TypeTypeContext) -> (v: {}) {
        obj := ""
        obj = Visit(context.GetChild(0)):Str
        <- (obj)
    }

    VisitTypeReference(context: TypeReferenceContext) -> (v: {}) {
        obj := "ref "
        ? context.typeNullable() >< () {
            obj += Visit(context.typeNullable())
        } context.typeNotNull() >< () {
            obj += Visit(context.typeNotNull())
        }
        <- (obj)
    }

    VisitTypeNullable(context: TypeNullableContext) -> (v: {}) {
        obj := ""
        obj = Visit(context.typeNotNull()):Str
        ? context.typeNotNull().GetChild(0) == :TypeBasicContext &
            context.typeNotNull().GetChild(0).GetText() >< "{}" &
            context.typeNotNull().GetChild(0).GetText() >< "Str" {
            obj += "?"
        }
        <- (obj)
    }

    VisitTypeTuple(context: TypeTupleContext) -> (v: {}) {
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

    VisitGetType(context: GetTypeContext) -> (v: {}) {
        r := Result{data = "System.Type"}
        ? context.typeType() == () {
            r.text = ""Visit(context.expression()):Result.text".GetType()"
        } _ {
            r.text = "typeof("Visit(context.typeType())")"
        }
        <- (r)
    }
    
    VisitTypeArray(context: TypeArrayContext) -> (v: {}) {
        obj := ""
        obj += ""Visit(context.typeType())"[]"
        <- (obj)
    }

    VisitTypeList(context: TypeListContext) -> (v: {}) {
        obj := ""
        obj += ""Lst"<"Visit(context.typeType())">"
        <- (obj)
    }

    VisitTypeSet(context: TypeSetContext) -> (v: {}) {
        obj := ""
        obj += ""Set"<"Visit(context.typeType())">"
        <- (obj)
    }

    VisitTypeDictionary(context: TypeDictionaryContext) -> (v: {}) {
        obj := ""
        obj += ""Dic"<"Visit(context.typeType(0))","Visit(context.typeType(1))">"
        <- (obj)
    }

    VisitTypePackage(context: TypePackageContext) -> (v: {}) {
        obj := ""
        obj += Visit(context.nameSpaceItem())
        ? context.templateCall() >< () {
            obj += Visit(context.templateCall())
        }
        <- (obj)
    }

    VisitTypeFunction(context: TypeFunctionContext) -> (v: {}) {
        obj := ""
        in := Visit(context.typeFunctionParameterClause(0)):Str
        out := Visit(context.typeFunctionParameterClause(1)):Str
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

    VisitTypeAny(context: TypeAnyContext) -> (v: {}) {
        <- (Any)
    }

    VisitTypeFunctionParameterClause(context: TypeFunctionParameterClauseContext) -> (v: {}) {
        obj := ""
        [0 <= context.typeType().Length - 1] @ i {
            p := Visit(context.typeType(i)):Str
            ? i == 0 {
                obj += p
            } _ {
                obj += ", "p""
            }
        }
        <- (obj)
    }

    VisitTypeBasic(context: TypeBasicContext) -> (v: {}) {
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
        } _ {
            obj = Any
        }
        <- (obj)
    }
}
