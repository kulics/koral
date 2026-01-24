// MARK: - Type Declaration Code Generation Extension

extension CodeGen {
  
  /// Generate struct type declaration with copy and drop functions
  func generateTypeDeclaration(
    _ identifier: Symbol,
    _ parameters: [Symbol]
  ) {
    let name = identifier.qualifiedName
    
    // Generate struct definition
    appendToBuffer("struct \(name) {\n")
    withIndent {
      for param in parameters {
        addIndent()
        appendToBuffer("\(getCType(param.type)) \(sanitizeIdentifier(param.name));\n")
      }
    }
    appendToBuffer("};\n\n")

    // Generate copy function
    appendToBuffer("struct \(name) __koral_\(name)_copy(const struct \(name) *self) {\n")
    withIndent {
      appendToBuffer("    struct \(name) result;\n")
      for param in parameters {
        let fieldName = sanitizeIdentifier(param.name)
        if case .structure(let decl) = param.type {
          let qualifiedFieldTypeName = decl.qualifiedName
          appendToBuffer("    result.\(fieldName) = __koral_\(qualifiedFieldTypeName)_copy(&self->\(fieldName));\n")
        } else if case .reference(_) = param.type {
          appendToBuffer("    result.\(fieldName) = self->\(fieldName);\n")
          appendToBuffer("    __koral_retain(result.\(fieldName).control);\n")
        } else {
          appendToBuffer("    result.\(fieldName) = self->\(fieldName);\n")
        }
      }
      appendToBuffer("    return result;\n")
    }
    appendToBuffer("}\n\n")

    // Generate drop function
    appendToBuffer("void __koral_\(name)_drop(void* raw_self) {\n")
    withIndent {
      appendToBuffer("    struct \(name)* self = (struct \(name)*)raw_self;\n")

      // Call user defined drop if exists
      if let userDrop = getUserDefinedDrop(for: name) {
          appendToBuffer("    {\n")
          appendToBuffer("        void \(userDrop)(struct Ref);\n")
          appendToBuffer("        struct Ref r;\n")
          appendToBuffer("        r.ptr = self;\n")
          appendToBuffer("        r.control = NULL;\n")
          appendToBuffer("        \(userDrop)(r);\n")
          appendToBuffer("    }\n")
      }

      for param in parameters {
        let fieldName = sanitizeIdentifier(param.name)
        if case .structure(let decl) = param.type {
          let qualifiedFieldTypeName = decl.qualifiedName
          appendToBuffer("    __koral_\(qualifiedFieldTypeName)_drop(&self->\(fieldName));\n")
        } else if case .reference(_) = param.type {
          appendToBuffer("    __koral_release(self->\(fieldName).control);\n")
        }
      }
    }
    appendToBuffer("}\n\n")
  }

  /// Generate union type declaration with copy and drop functions
  func generateUnionDeclaration(_ identifier: Symbol, _ cases: [UnionCase]) {
    let name = identifier.qualifiedName
    appendToBuffer("struct \(name) {\n")
    withIndent {
      addIndent()
      appendToBuffer("intptr_t tag;\n")
      addIndent()
      appendToBuffer("union {\n")
      withIndent {
        for c in cases {
            let caseName = sanitizeIdentifier(c.name)
            if !c.parameters.isEmpty {
                addIndent()
                appendToBuffer("struct {\n")
                withIndent {
                    for param in c.parameters {
                        addIndent()
                        appendToBuffer("\(getCType(param.type)) \(sanitizeIdentifier(param.name));\n")
                    }
                }
                addIndent()
                appendToBuffer("} \(caseName);\n")
            } else {
                 addIndent()
                 appendToBuffer("struct {} \(caseName);\n")
            }
        }
      }
      addIndent()
      appendToBuffer("} data;\n")
    }
    appendToBuffer("};\n\n")

    // Generate Copy
    appendToBuffer("struct \(name) __koral_\(name)_copy(const struct \(name) *self) {\n")
    withIndent {
        appendToBuffer("    struct \(name) result;\n")
        appendToBuffer("    result.tag = self->tag;\n")
        appendToBuffer("    switch (self->tag) {\n")
        for (index, c) in cases.enumerated() {
             let caseName = sanitizeIdentifier(c.name)
             appendToBuffer("    case \(index): // \(c.name)\n")
             if !c.parameters.isEmpty {
                 for param in c.parameters {
                     let fieldName = sanitizeIdentifier(param.name)
                     let fieldPath = "self->data.\(caseName).\(fieldName)"
                     let resultPath = "result.data.\(caseName).\(fieldName)"
                     if case .structure(let decl) = param.type {
                         let qualifiedFieldTypeName = decl.qualifiedName
                         appendToBuffer("        \(resultPath) = __koral_\(qualifiedFieldTypeName)_copy(&\(fieldPath));\n")
                     } else if case .union(let decl) = param.type {
                        let qualifiedFieldTypeName = decl.qualifiedName
                        appendToBuffer("        \(resultPath) = __koral_\(qualifiedFieldTypeName)_copy(&\(fieldPath));\n")
                     } else if case .reference(_) = param.type {
                         appendToBuffer("        \(resultPath) = \(fieldPath);\n")
                         appendToBuffer("        __koral_retain(\(resultPath).control);\n")
                     } else {
                         appendToBuffer("        \(resultPath) = \(fieldPath);\n")
                     }
                 }
             }
             appendToBuffer("        break;\n")
        }
        appendToBuffer("    }\n")
        appendToBuffer("    return result;\n")
    }
    appendToBuffer("}\n\n")

    // Generate Drop
    appendToBuffer("void __koral_\(name)_drop(void* raw_self) {\n")
    withIndent {
        appendToBuffer("    struct \(name)* self = (struct \(name)*)raw_self;\n")

        // Call user defined drop if exists
        if let userDrop = getUserDefinedDrop(for: name) {
            appendToBuffer("    {\n")
            appendToBuffer("        void \(userDrop)(struct Ref);\n")
            appendToBuffer("        struct Ref r;\n")
            appendToBuffer("        r.ptr = self;\n")
            appendToBuffer("        r.control = NULL;\n")
            appendToBuffer("        \(userDrop)(r);\n")
            appendToBuffer("    }\n")
        }

        appendToBuffer("    switch (self->tag) {\n")
        for (index, c) in cases.enumerated() {
             let caseName = sanitizeIdentifier(c.name)
             appendToBuffer("    case \(index): // \(c.name)\n")
             for param in c.parameters {
                 let fieldName = sanitizeIdentifier(param.name)
                 let fieldPath = "self->data.\(caseName).\(fieldName)"
                 if case .structure(let decl) = param.type {
                     let qualifiedFieldTypeName = decl.qualifiedName
                     appendToBuffer("        __koral_\(qualifiedFieldTypeName)_drop(&\(fieldPath));\n")
                 } else if case .union(let decl) = param.type {
                     let qualifiedFieldTypeName = decl.qualifiedName
                     appendToBuffer("        __koral_\(qualifiedFieldTypeName)_drop(&\(fieldPath));\n")
                 } else if case .reference(_) = param.type {
                     appendToBuffer("        __koral_release(\(fieldPath).control);\n")
                 }
             }
             appendToBuffer("        break;\n")
        }
        appendToBuffer("    }\n")
    }
    appendToBuffer("}\n\n")
  }

  /// Generate union constructor code
  func generateUnionConstructor(type: Type, caseName: String, args: [TypedExpressionNode]) -> String {
      guard case .union(let decl) = type else { fatalError() }
      let typeName = decl.qualifiedName
      let cases = decl.cases
      
      // Calculate tag index
      let tagIndex = cases.firstIndex(where: { $0.name == caseName })!
      
      let result = nextTemp()
      addIndent()
      appendToBuffer("struct \(typeName) \(result);\n")
      addIndent()
      appendToBuffer("\(result).tag = \(tagIndex);\n")
      
      // Assign members
      let caseInfo = cases[tagIndex]
      let escapedCaseName = sanitizeIdentifier(caseName)
      
      if !args.isEmpty {
          let unionMemberPath = "\(result).data.\(escapedCaseName)"
          for (argExpr, param) in zip(args, caseInfo.parameters) {
              let argResult = generateExpressionSSA(argExpr)
              let fieldName = sanitizeIdentifier(param.name)
              
              addIndent()
              if case .structure(let structDecl) = param.type {
                   if argExpr.valueCategory == .lvalue {
                       appendToBuffer("\(unionMemberPath).\(fieldName) = __koral_\(structDecl.qualifiedName)_copy(&\(argResult));\n")
                   } else {
                       appendToBuffer("\(unionMemberPath).\(fieldName) = \(argResult);\n")
                   }
              } else if case .reference(_) = param.type {
                   appendToBuffer("\(unionMemberPath).\(fieldName) = \(argResult);\n")
                   if argExpr.valueCategory == .lvalue {
                       addIndent()
                       appendToBuffer("__koral_retain(\(unionMemberPath).\(fieldName).control);\n")
                   }
              } else {
                   appendToBuffer("\(unionMemberPath).\(fieldName) = \(argResult);\n")
              }
          }
      }
      
      return result
  }
}
