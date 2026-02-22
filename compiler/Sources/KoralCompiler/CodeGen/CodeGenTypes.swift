// MARK: - Type Declaration Code Generation Extension

extension CodeGen {
  
  /// Generate struct type declaration with copy and drop functions
  func generateTypeDeclaration(
    _ identifier: Symbol,
    _ parameters: [Symbol]
  ) {
    let name: String
    if case .structure(let defId) = identifier.type {
      name = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
    } else {
      name = cIdentifier(for: identifier)
    }
    if case .structure(let defId) = identifier.type,
       context.isGenericInstantiation(defId) == true || (context.getTypeArguments(defId)?.isEmpty == false) {
      appendToBuffer("// Generic instantiation: \(context.getDebugName(identifier.type))\n")
    }
    
    // Generate struct definition
    appendToBuffer("struct \(name) {\n")
    withIndent {
      for param in parameters {
        addIndent()
        let paramName = context.getName(param.defId) ?? "<unknown>"
        appendToBuffer("\(cTypeName(param.type)) \(sanitizeCIdentifier(paramName));\n")
      }
    }
    appendToBuffer("};\n\n")

    // Generate copy function
    appendToBuffer("struct \(name) __koral_\(name)_copy(const struct \(name) *self) {\n")
    withIndent {
      appendToBuffer("    struct \(name) result;\n")
      for param in parameters {
        let fieldName = sanitizeCIdentifier(context.getName(param.defId) ?? "<unknown>")
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
          appendToBuffer("        void \(userDrop)(struct __koral_Ref);\n")
          appendToBuffer("        struct __koral_Ref r;\n")
          appendToBuffer("        r.ptr = self;\n")
          appendToBuffer("        r.control = NULL;\n")
          appendToBuffer("        \(userDrop)(r);\n")
          appendToBuffer("    }\n")
      }

      for param in parameters {
        let fieldName = sanitizeCIdentifier(context.getName(param.defId) ?? "<unknown>")
        appendDropStatement(for: param.type, value: "self->\(fieldName)")
      }
    }
    appendToBuffer("}\n\n")
  }

  /// Generate union type declaration with copy and drop functions
  func generateUnionDeclaration(_ identifier: Symbol, _ cases: [UnionCase]) {
    let name: String
    if case .union(let defId) = identifier.type {
      name = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
    } else {
      name = cIdentifier(for: identifier)
    }
    if case .union(let defId) = identifier.type,
       context.isGenericInstantiation(defId) == true || (context.getTypeArguments(defId)?.isEmpty == false) {
      appendToBuffer("// Generic instantiation: \(context.getDebugName(identifier.type))\n")
    }
    appendToBuffer("struct \(name) {\n")
    withIndent {
      addIndent()
      appendToBuffer("intptr_t tag;\n")
      addIndent()
      appendToBuffer("union {\n")
      withIndent {
        for c in cases {
            let caseName = sanitizeCIdentifier(c.name)
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
                        appendToBuffer("\(cTypeName(param.type)) \(sanitizeCIdentifier(param.name));\n")
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
             let caseName = sanitizeCIdentifier(c.name)
             appendToBuffer("    case \(index): // \(c.name)\n")
             // Filter out Void type parameters
             let nonVoidParams = c.parameters.filter { param in
                 if case .void = param.type { return false }
                 return true
             }
             if !nonVoidParams.isEmpty {
                 for param in nonVoidParams {
                     let fieldName = sanitizeCIdentifier(param.name)
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
          appendToBuffer("        void \(userDrop)(struct __koral_Ref);\n")
          appendToBuffer("        struct __koral_Ref r;\n")
            appendToBuffer("        r.ptr = self;\n")
            appendToBuffer("        r.control = NULL;\n")
            appendToBuffer("        \(userDrop)(r);\n")
            appendToBuffer("    }\n")
        }

        appendToBuffer("    switch (self->tag) {\n")
        for (index, c) in cases.enumerated() {
             let caseName = sanitizeCIdentifier(c.name)
             appendToBuffer("    case \(index): // \(c.name)\n")
             // Filter out Void type parameters
             let nonVoidParams = c.parameters.filter { param in
                 if case .void = param.type { return false }
                 return true
             }
             for param in nonVoidParams {
               let fieldName = sanitizeCIdentifier(param.name)
               let fieldPath = "self->data.\(caseName).\(fieldName)"
               appendDropStatement(for: param.type, value: fieldPath)
             }
             appendToBuffer("        break;\n")
        }
        appendToBuffer("    }\n")
    }
    appendToBuffer("}\n\n")
  }

  /// Generate foreign struct declaration without copy/drop
  func generateForeignStructDeclaration(
    _ identifier: Symbol,
    _ fields: [(name: String, type: Type)]
  ) {
    let name: String
    if case .structure(let defId) = identifier.type {
      name = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
    } else {
      name = cIdentifier(for: identifier)
    }

    appendToBuffer("struct \(name) {\n")
    withIndent {
      for field in fields {
        addIndent()
        appendToBuffer("\(cTypeName(field.type)) \(sanitizeCIdentifier(field.name));\n")
      }
    }
    appendToBuffer("};\n\n")
  }

  /// Generate union constructor code
  func generateUnionConstructor(type: Type, caseName: String, args: [TypedExpressionNode]) -> String {
      guard case .union(let defId) = type else { fatalError() }
      let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
      let cases = context.getUnionCases(defId) ?? []
      
      // Calculate tag index
      let tagIndex = cases.firstIndex(where: { $0.name == caseName })!
      
      let cType = "struct \(typeName)"
      let result = nextTempWithDecl(cType: cType)
      addIndent()
      appendToBuffer("\(result).tag = \(tagIndex);\n")
      
      // Assign members
      let caseInfo = cases[tagIndex]
      let escapedCaseName = sanitizeCIdentifier(caseName)
      
      // Filter out Void type parameters and their corresponding args
      var nonVoidArgsAndParams: [(TypedExpressionNode, (name: String, type: Type, access: AccessModifier))] = []
      for (argExpr, param) in zip(args, caseInfo.parameters) {
          if case .void = param.type { continue }
          nonVoidArgsAndParams.append((argExpr, param))
      }
      
      if !nonVoidArgsAndParams.isEmpty {
          let unionMemberPath = "\(result).data.\(escapedCaseName)"
          for (argExpr, param) in nonVoidArgsAndParams {
              let argResult = generateExpressionSSA(argExpr)
              let fieldName = sanitizeCIdentifier(param.name)
              
              if argExpr.valueCategory == .lvalue {
                  // Use appendCopyAssignment which handles all types correctly:
                  // struct (deep copy), union (deep copy), reference (retain),
                  // function/closure (closure_retain), weakReference (weak_retain), etc.
                  appendCopyAssignment(for: param.type, source: argResult, dest: "\(unionMemberPath).\(fieldName)")
              } else {
                  addIndent()
                  appendToBuffer("\(unionMemberPath).\(fieldName) = \(argResult);\n")
              }
          }
      }
      
      return result
  }
}
