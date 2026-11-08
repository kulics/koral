// MARK: - Type Declaration Code Generation Extension

extension CodeGen {

  private func appendManagedNominalCopyFunction(name: String) {
    appendToBuffer("struct \(name) __koral_\(name)_copy(const struct \(name) *self) {\n")
    withIndent {
      appendToBuffer("    struct \(name) result = *self;\n")
      appendToBuffer("    __koral_retain_value(result.ptr);\n")
      appendToBuffer("    return result;\n")
    }
    appendToBuffer("}\n\n")
  }

  private func appendManagedNominalDropFunction(name: String) {
    appendToBuffer("void __koral_\(name)_drop(struct \(name)* self) {\n")
    withIndent {
      // 头里不存析构函数：drop glue 在释放调用点单态化后传进来。
      // 这里 `self->ptr` 指向的是本类型自己的 payload 块。
      appendToBuffer("    __koral_release_value(self->ptr, (__koral_Dtor)__koral_\(name)_payload_drop);\n")
    }
    appendToBuffer("}\n\n")
  }

  private func appendManagedNominalUserDropPrelude(name: String, userDrop: String) {
    // 借用形态：把 payload 交给用户的 `drop(self)`，不接管所有权。
    // `__koral_self` 是栈局部且从不被 drop，所以不需要 control 哨兵。
    appendToBuffer("    struct \(name) __koral_self;\n")
    appendToBuffer("    __koral_self.ptr = raw_payload;\n")
    appendToBuffer("    {\n")
    appendToBuffer("        void \(userDrop)(struct \(name)*);\n")
    appendToBuffer("        \(userDrop)(&__koral_self);\n")
    appendToBuffer("    }\n")
  }

  private func appendManagedStructPayloadDropFunction(name: String, payloadName: String, parameters: [Symbol]) {
    appendToBuffer("static void __koral_\(name)_payload_drop(void* raw_payload) {\n")
    withIndent {
      appendToBuffer("    struct \(payloadName)* self = (struct \(payloadName)*)raw_payload;\n")
      if let userDrop = getUserDefinedDrop(for: name) {
        appendManagedNominalUserDropPrelude(name: name, userDrop: userDrop)
      }
      for param in parameters {
        let fieldName = sanitizeCIdentifier(context.getName(param.defId) ?? "<unknown>")
        appendDropStatement(for: param.type, value: "self->\(fieldName)")
      }
    }
    appendToBuffer("}\n\n")
  }

  private func appendManagedEnumPayloadDropFunction(name: String, payloadName: String, cases: [EnumCase]) {
    appendToBuffer("static void __koral_\(name)_payload_drop(void* raw_payload) {\n")
    withIndent {
      appendToBuffer("    struct \(payloadName)* self = (struct \(payloadName)*)raw_payload;\n")
      if let userDrop = getUserDefinedDrop(for: name) {
        appendManagedNominalUserDropPrelude(name: name, userDrop: userDrop)
      }
      if let niche = enumNicheLayout(cases: cases) {
        let valueExpr = "self->data.\(sanitizeCIdentifier(niche.payloadCaseName)).\(sanitizeCIdentifier(niche.payloadFieldName))"
        appendToBuffer("    switch (\(nicheTagExpression(layout: niche, valueExpr: valueExpr))) {\n")
      } else {
        appendToBuffer("    switch (self->tag) {\n")
      }
      for (index, c) in cases.enumerated() {
        let caseName = sanitizeCIdentifier(c.name)
        appendToBuffer("    case \(index): // \(c.name)\n")
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

  private func generateManagedStructDeclaration(name: String, type: Type, parameters: [Symbol]) {
    let payloadName = managedPayloadTypeName(for: type)
    appendToBuffer("struct \(payloadName) {\n")
    withIndent {
      if context.isLockedType(type) {
        // The built-in object lock is the payload's hidden first field
        // (concurrency-design.md): the lock address is the payload pointer
        // (first field, offset 0); codegen emits `&payload->__lock`.
        // Destruction needs no action (the lock holds no resources).
        addIndent()
        appendToBuffer("struct __koral_Lock __lock;\n")
      }
      for param in parameters {
        addIndent()
        let paramName = context.getName(param.defId) ?? "<unknown>"
        appendToBuffer("\(cTypeName(param.type)) \(sanitizeCIdentifier(paramName));\n")
      }
    }
    appendToBuffer("};\n\n")
    appendManagedNominalCopyFunction(name: name)
    appendManagedStructPayloadDropFunction(name: name, payloadName: payloadName, parameters: parameters)
    appendManagedNominalDropFunction(name: name)
  }

  private func generateManagedEnumDeclaration(name: String, type: Type, cases: [EnumCase]) {
    let payloadName = managedPayloadTypeName(for: type)
    let niche = enumNicheLayout(cases: cases)
    appendToBuffer("struct \(payloadName) {\n")
    withIndent {
      if niche == nil {
        addIndent()
        appendToBuffer("intptr_t tag;\n")
      }
      addIndent()
      appendToBuffer("union {\n")
      withIndent {
        for c in cases {
          let caseName = sanitizeCIdentifier(c.name)
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
    // For enums, pass nil parameters since enum fields are in cases (handled differently)
    appendManagedNominalCopyFunction(name: name)
    appendManagedEnumPayloadDropFunction(name: name, payloadName: payloadName, cases: cases)
    appendManagedNominalDropFunction(name: name)
  }
  
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

    if usesManagedNominalRepresentation(identifier.type) {
      generateManagedStructDeclaration(name: name, type: identifier.type, parameters: parameters)
      return
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
    appendToBuffer("void __koral_\(name)_drop(struct \(name)* self) {\n")
    withIndent {
      // Call user defined drop if exists
      if let userDrop = getUserDefinedDrop(for: name) {
          appendToBuffer("    {\n")
          appendToBuffer("        void \(userDrop)(struct \(name)*);\n")
          appendToBuffer("        \(userDrop)(self);\n")
          appendToBuffer("    }\n")
      }

      for param in parameters {
        let fieldName = sanitizeCIdentifier(context.getName(param.defId) ?? "<unknown>")
        appendDropStatement(for: param.type, value: "self->\(fieldName)")
      }
    }
    appendToBuffer("}\n\n")
  }

  /// Generate enum type declaration with copy and drop functions
  func generateEnumDeclaration(_ identifier: Symbol, _ cases: [EnumCase]) {
    let name: String
    if case .`enum`(let defId) = identifier.type {
      name = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
    } else {
      name = cIdentifier(for: identifier)
    }
    if case .`enum`(let defId) = identifier.type,
       context.isGenericInstantiation(defId) == true || (context.getTypeArguments(defId)?.isEmpty == false) {
      appendToBuffer("// Generic instantiation: \(context.getDebugName(identifier.type))\n")
    }

    if usesManagedNominalRepresentation(identifier.type) {
      generateManagedEnumDeclaration(name: name, type: identifier.type, cases: cases)
      return
    }

    let niche = enumNicheLayout(cases: cases)
    appendToBuffer("struct \(name) {\n")
    withIndent {
      if niche == nil {
        addIndent()
        appendToBuffer("intptr_t tag;\n")
      }
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
        if let niche {
          appendToBuffer("    switch (\(nicheTagExpression(layout: niche, valueExpr: "self->data.\(sanitizeCIdentifier(niche.payloadCaseName)).\(sanitizeCIdentifier(niche.payloadFieldName))"))) {\n")
        } else {
          appendToBuffer("    result.tag = self->tag;\n")
          appendToBuffer("    switch (self->tag) {\n")
        }
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
             } else if let niche {
                 // niche 布局下空 case 没有自己的存储，必须把空位模式写回 result，
                 // 否则 result 带着脏值，后续 niche 测试会误判成 payload case。
                 let payloadField = "data.\(sanitizeCIdentifier(niche.payloadCaseName)).\(sanitizeCIdentifier(niche.payloadFieldName))"
                 appendToBuffer("        \(nicheNullAssignment(niche.payloadFieldType, fieldPath: "result.\(payloadField)"))")
             }
             appendToBuffer("        break;\n")
        }
        appendToBuffer("    }\n")
        appendToBuffer("    return result;\n")
    }
    appendToBuffer("}\n\n")

    // Generate Drop
    appendToBuffer("void __koral_\(name)_drop(struct \(name)* self) {\n")
    withIndent {
        // Call user defined drop if exists
        if let userDrop = getUserDefinedDrop(for: name) {
            appendToBuffer("    {\n")
          appendToBuffer("        void \(userDrop)(struct \(name)*);\n")
            appendToBuffer("        \(userDrop)(self);\n")
            appendToBuffer("    }\n")
        }

        if let niche {
          appendToBuffer("    switch (\(nicheTagExpression(layout: niche, valueExpr: "self->data.\(sanitizeCIdentifier(niche.payloadCaseName)).\(sanitizeCIdentifier(niche.payloadFieldName))"))) {\n")
        } else {
          appendToBuffer("    switch (self->tag) {\n")
        }
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

}
