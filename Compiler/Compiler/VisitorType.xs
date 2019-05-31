\Compiler <- {
    Antlr4\Runtime
    Antlr4\Runtime\Misc
    System
    Library
    Compiler.XsParser
    Compiler.Compiler Static
}

XsVisitor -> {
} ...XsBaseVisitor<{}> {
    VisitType(context: TypeContext) -> ({}) {
        obj := ""
        obj = Visit(context.GetChild(0)):Str
        <- (obj)
    }

    VisitTypeReference(context: TypeReferenceContext) -> ({}) {
        obj := "ref "
        ? context.typeNullable() >< () {
            obj += Visit(context.typeNullable())
        } context.typeNotNull() >< () {
            obj += Visit(context.typeNotNull())
        }
        <- (obj)
    }

    VisitTypeNullable(context: TypeNullableContext) -> ({}) {
        obj := ""
        obj = Visit(context.typeNotNull()):Str
        ? context.typeNotNull().GetChild(0) == :TypeBasicContext &
            context.typeNotNull().GetChild(0).GetText() >< "{}" &
            context.typeNotNull().GetChild(0).GetText() >< "Str" {
            obj += "?"
        }
        <- (obj)
    }

    VisitTypeTuple(context: TypeTupleContext) -> ({}) {
        obj := ""
        obj += "("
        [0 < context.type().Length] @ i {
            ? i == 0 {
                obj += Visit(context.type(i))
            } _ {
                obj += ","Visit(context.type(i))""
            }
        }
        obj += ")"
        <- (obj)
    }

    VisitGetType(context: GetTypeContext) -> ({}) {
        r := Result{data = "System.Type"}
        ? context.type() == () {
            r.text = ""Visit(context.expression()):Result.text".GetType()"
        } else {
            r.text = "typeof("Visit(context.type())")"
        }
        <- (r)
    }
    
    VisitTypeArray(context: TypeArrayContext) -> ({}) {
        obj := ""
        obj += ""Visit(context.type())"[]"
        <- (obj)
    }

    VisitTypeList(context: TypeListContext) -> ({}) {
        obj := ""
        obj += ""Lst"<"Visit(context.type())">"
        <- (obj)
    }

    VisitTypeSet(context: TypeSetContext) -> ({}) {
        obj := ""
        obj += ""Set"<"Visit(context.type())">"
        <- (obj)
    }

    VisitTypeDictionary(context: TypeDictionaryContext) -> ({}) {
        obj := ""
        obj += ""Dic"<"Visit(context.type(0))","Visit(context.type(1))">"
        <- (obj)
    }

    VisitTypePackage(context: TypePackageContext) -> ({}) {
        obj := ""
        obj += Visit(context.nameSpaceItem())
        ? context.templateCall() >< () {
            obj += Visit(context.templateCall())
        }
        <- (obj)
    }

    VisitTypeFunction(context: TypeFunctionContext) -> ({}) {
        obj := ""
        in := Visit(context.typeFunctionParameterClause(0)):Str
        out := Visit(context.typeFunctionParameterClause(1)):Str
        ? context.t.Type == ArrowRight {
            ? out.Length == 0 {
                ? in.Length == 0 {
                    obj = "Action"
                } _ {
                    obj = "Action<"in">"
                }
            } _ {
                ? out.index of(",") >= 0 {
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

    VisitTypeAny(context: TypeAnyContext) -> ({}) {
        <- (Any)
    }

    VisitTypeFunctionParameterClause(context: TypeFunctionParameterClauseContext) -> ({}) {
        obj := ""
        [0 <= context.type().Length - 1] @ i {
            p := Visit(context.type(i)):Str
            ? i == 0 {
                obj += p
            } _ {
                obj += ", "p""
            }
        }
        <- (obj)
    }

    VisitTypeBasic(context: TypeBasicContext) -> ({}) {
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
