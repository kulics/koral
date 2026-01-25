// MARK: - Type Declaration Code Generation Extension

extension CodeGen {
  
  /// Generate struct type declaration with copy and drop functions
  func generateTypeDeclaration(
    _ identifier: Symbol,
    _ parameters: [Symbol]
  ) {
    let name: String
    if case .structure(let decl) = identifier.type {
      name = cIdentifier(for: decl)
    } else {
      name = cIdentifier(for: identifier)
    }
    if case .structure(let decl) = identifier.type,
       decl.isGenericInstantiation || (decl.typeArguments?.isEmpty == false) {
      appendToBuffer("// Generic instantiation: \(identifier.type.debugName)\n")
    }
    
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
        appendCopyAssignment(
          for: param.type,
          source: "self->\(fieldName)",
          dest: "result.\(fieldName)"
        )
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
        appendDropStatement(for: param.type, value: "self->\(fieldName)")
      }
    }
    appendToBuffer("}\n\n")
  }

  /// Generate union type declaration with copy and drop functions
  func generateUnionDeclaration(_ identifier: Symbol, _ cases: [UnionCase]) {
    let name: String
    if case .union(let decl) = identifier.type {
      name = cIdentifier(for: decl)
    } else {
      name = cIdentifier(for: identifier)
    }
    if case .union(let decl) = identifier.type,
       decl.isGenericInstantiation || (decl.typeArguments?.isEmpty == false) {
      appendToBuffer("// Generic instantiation: \(identifier.type.debugName)\n")
    }
    appendToBuffer("struct \(name) {\n")
    withIndent {
      addIndent()
      appendToBuffer("intptr_t tag;\n")
      addIndent()
      appendToBuffer("union {\n")
      withIndent {
        for c in cases {
            let caseName = sanitizeIdentifier(c.name)
            // Filter out Void type parameters - they don't need storage
            let nonVoidParams = c.parameters.filter { param in
                if case .void = param.type { return false }
                return true
            }
            if !nonVoidParams.isEmpty {
                addIndent()
                appendToBuffer("struct {\n")
                withIndent {
                    for param in nonVoidParams {
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
             // Filter out Void type parameters
             let nonVoidParams = c.parameters.filter { param in
                 if case .void = param.type { return false }
                 return true
             }
             if !nonVoidParams.isEmpty {
                 for param in nonVoidParams {
                     let fieldName = sanitizeIdentifier(param.name)
                     let fieldPath = "self->data.\(caseName).\(fieldName)"
                     let resultPath = "result.data.\(caseName).\(fieldName)"
                     appendCopyAssignment(
                       for: param.type,
                       source: fieldPath,
                       dest: resultPath
                     )
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
             // Filter out Void type parameters
             let nonVoidParams = c.parameters.filter { param in
                 if case .void = param.type { return false }
                 return true
             }
             for param in nonVoidParams {
               let fieldName = sanitizeIdentifier(param.name)
               let fieldPath = "self->data.\(caseName).\(fieldName)"
               appendDropStatement(for: param.type, value: fieldPath)
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
      let typeName = cIdentifier(for: decl)
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
      
      // Filter out Void type parameters and their corresponding args
      var nonVoidArgsAndParams: [(TypedExpressionNode, (name: String, type: Type))] = []
      for (argExpr, param) in zip(args, caseInfo.parameters) {
          if case .void = param.type { continue }
          nonVoidArgsAndParams.append((argExpr, param))
      }
      
      if !nonVoidArgsAndParams.isEmpty {
          let unionMemberPath = "\(result).data.\(escapedCaseName)"
          for (argExpr, param) in nonVoidArgsAndParams {
              let argResult = generateExpressionSSA(argExpr)
              let fieldName = sanitizeIdentifier(param.name)
              
              addIndent()
              if case .structure(let structDecl) = param.type {
                   if argExpr.valueCategory == .lvalue {
                     let structTypeName = cIdentifier(for: structDecl)
                     appendToBuffer("\(unionMemberPath).\(fieldName) = __koral_\(structTypeName)_copy(&\(argResult));\n")
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
