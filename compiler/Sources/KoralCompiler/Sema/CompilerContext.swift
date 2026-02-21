import Foundation

/// CompilerContext - Unified query/update context for DefId and type info.
///
/// Provides immutable query APIs and explicit update APIs to avoid reliance
/// on global mutable state and to support parallel compilation.
public final class CompilerContext: @unchecked Sendable {
    public private(set) var defIdMap: DefIdMap

    public init(defIdMap: DefIdMap = DefIdMap()) {
        self.defIdMap = defIdMap
    }

    // MARK: - DefIdMap Queries

    public func getName(_ defId: DefId) -> String? {
        defIdMap.getName(defId)
    }

    public func getModulePath(_ defId: DefId) -> [String]? {
        defIdMap.getModulePath(defId)
    }

    public func getSourceFile(_ defId: DefId) -> String? {
        defIdMap.getSourceFile(defId)
    }

    public func getKind(_ defId: DefId) -> DefKind? {
        defIdMap.getKind(defId)
    }

    public func getAccess(_ defId: DefId) -> AccessModifier? {
        defIdMap.getAccess(defId)
    }

    public func getSpan(_ defId: DefId) -> SourceSpan? {
        defIdMap.getSpan(defId)
    }

    public func getQualifiedName(_ defId: DefId) -> String? {
        defIdMap.getQualifiedName(defId)
    }

    public func getCIdentifier(_ defId: DefId) -> String? {
        defIdMap.getCIdentifier(defId)
    }

    public func getSymbolType(_ defId: DefId) -> Type? {
        defIdMap.getSymbolType(defId)
    }

    public func getSymbolKind(_ defId: DefId) -> SymbolKind? {
        defIdMap.getSymbolKind(defId)
    }

    public func getSymbolMethodKind(_ defId: DefId) -> CompilerMethodKind? {
        defIdMap.getSymbolMethodKind(defId)
    }

    public func isSymbolMutable(_ defId: DefId) -> Bool {
        defIdMap.isSymbolMutable(defId) ?? false
    }

    public func lookupDefId(
        modulePath: [String],
        name: String,
        sourceFile: String?
    ) -> DefId? {
        defIdMap.lookup(modulePath: modulePath, name: name, sourceFile: sourceFile)
    }

    public func lookupSymbol(
        name: String,
        sourceFile: String?,
        scope: UnifiedScope
    ) -> DefId? {
        scope.lookup(name, sourceFile: sourceFile)
    }

    public func allocateDefId(
        modulePath: [String],
        name: String,
        kind: DefKind,
        sourceFile: String,
        access: AccessModifier = .protected,
        span: SourceSpan = .unknown
    ) -> DefId {
        defIdMap.allocate(
            modulePath: modulePath,
            name: name,
            kind: kind,
            sourceFile: sourceFile,
            access: access,
            span: span
        )
    }

    public func createSymbol(
        name: String,
        modulePath: [String],
        sourceFile: String,
        type: Type,
        kind: SymbolKind,
        methodKind: CompilerMethodKind = .normal,
        access: AccessModifier = .protected,
        span: SourceSpan = .unknown,
        isMutable: Bool = false
    ) -> Symbol {
        let defKind: DefKind
        switch kind {
        case .function:
            defKind = .function
        case .variable:
            defKind = .variable
        case .type:
            if case .opaque = type {
                defKind = .type(.opaque)
            } else {
                defKind = .type(.structure)
            }
        case .module:
            defKind = .module
        }

        let lookupSourceFile = access == .private ? sourceFile : nil
        let defId = defIdMap.lookup(
            modulePath: modulePath,
            name: name,
            sourceFile: lookupSourceFile
        ) ?? defIdMap.allocate(
            modulePath: modulePath,
            name: name,
            kind: defKind,
            sourceFile: sourceFile,
            access: access,
            span: span
        )

        defIdMap.addSymbolInfo(
            defId: defId,
            type: type,
            kind: kind,
            methodKind: methodKind,
            isMutable: isMutable
        )

        return Symbol(defId: defId, type: type, kind: kind, methodKind: methodKind)
    }

    // MARK: - Typed Definition Queries

    public func getStructMembers(_ defId: DefId) -> [(name: String, type: Type, mutable: Bool, access: AccessModifier)]? {
        defIdMap.getStructMembers(defId)
    }

    public func getUnionCases(_ defId: DefId) -> [UnionCase]? {
        defIdMap.getUnionCases(defId)
    }

    public func getForeignStructFields(_ defId: DefId) -> [(name: String, type: Type)]? {
        defIdMap.getForeignStructFields(defId)
    }

    public func isForeignStruct(_ defId: DefId) -> Bool {
        defIdMap.isForeignStruct(defId)
    }

    public func setCname(_ defId: DefId, _ cname: String) {
        defIdMap.setCname(defId, cname)
    }

    public func getCname(_ defId: DefId) -> String? {
        defIdMap.getCname(defId)
    }

    public func isGenericInstantiation(_ defId: DefId) -> Bool? {
        defIdMap.isGenericInstantiation(defId)
    }

    public func getTypeArguments(_ defId: DefId) -> [Type]? {
        defIdMap.getTypeArguments(defId)
    }

    public func getTemplateName(_ defId: DefId) -> String? {
        return defIdMap.getTemplateName(defId)
    }

    // MARK: - Unified Updates

    public func setDefIdMap(_ map: DefIdMap) {
        defIdMap = map
    }

    public func updateStructInfo(
        defId: DefId,
        members: [(name: String, type: Type, mutable: Bool, access: AccessModifier)],
        isGenericInstantiation: Bool,
        typeArguments: [Type]?,
        templateName: String? = nil
    ) {
        let resolvedTemplateName = templateName ?? defIdMap.getTemplateName(defId)
        defIdMap.addStructInfo(
            defId: defId,
            members: members,
            isGenericInstantiation: isGenericInstantiation,
            typeArguments: typeArguments,
            templateName: resolvedTemplateName
        )
    }

    public func updateUnionInfo(
        defId: DefId,
        cases: [UnionCase],
        isGenericInstantiation: Bool,
        typeArguments: [Type]?,
        templateName: String? = nil
    ) {
        let resolvedTemplateName = templateName ?? defIdMap.getTemplateName(defId)
        defIdMap.addUnionInfo(
            defId: defId,
            cases: cases,
            isGenericInstantiation: isGenericInstantiation,
            typeArguments: typeArguments,
            templateName: resolvedTemplateName
        )
    }

    public func updateForeignStructFields(defId: DefId, fields: [(name: String, type: Type)]) {
        defIdMap.setForeignStructFields(defId, fields)
    }

    // MARK: - Type Queries

    public func getTypeName(_ type: Type) -> String {
        switch type {
        case .structure(let defId):
            return defIdMap.getName(defId) ?? "<unknown>"
        case .union(let defId):
            return defIdMap.getName(defId) ?? "<unknown>"
        case .opaque(let defId):
            return defIdMap.getName(defId) ?? "<unknown>"
        default:
            return type.description
        }
    }

    public func getDebugName(_ type: Type) -> String {
        switch type {
        case .int: return "Int"
        case .int8: return "Int8"
        case .int16: return "Int16"
        case .int32: return "Int32"
        case .int64: return "Int64"
        case .uint: return "UInt"
        case .uint8: return "UInt8"
        case .uint16: return "UInt16"
        case .uint32: return "UInt32"
        case .uint64: return "UInt64"
        case .float32: return "Float32"
        case .float64: return "Float64"
        case .bool: return "Bool"
        case .void: return "Void"
        case .never: return "Never"
        case .function(let params, let returns):
            let paramStr = params.map { getDebugName($0.type) }.joined(separator: ", ")
            return "(\(paramStr)) -> \(getDebugName(returns))"
        case .reference(let inner): return "\(getDebugName(inner)) ref"
        case .pointer(let element): return "\(getDebugName(element)) ptr"
        case .weakReference(let inner): return "\(getDebugName(inner)) weakref"
        case .structure(let defId):
            var name = defIdMap.getName(defId) ?? "<unknown>"
            if let typeArgs = defIdMap.getTypeArguments(defId), !typeArgs.isEmpty {
                let argsStr = typeArgs.map { getDebugName($0) }.joined(separator: ", ")
                name += "[\(argsStr)]"
            }
            return name
        case .union(let defId):
            var name = defIdMap.getName(defId) ?? "<unknown>"
            if let typeArgs = defIdMap.getTypeArguments(defId), !typeArgs.isEmpty {
                let argsStr = typeArgs.map { getDebugName($0) }.joined(separator: ", ")
                name += "[\(argsStr)]"
            }
            return name
        case .opaque(let defId):
            return defIdMap.getName(defId) ?? "<unknown>"
        case .genericParameter(let name):
            return name
        case .genericStruct(let template, let args):
            let argsStr = args.map { getDebugName($0) }.joined(separator: ", ")
            return "\(template)[\(argsStr)]"
        case .genericUnion(let template, let args):
            let argsStr = args.map { getDebugName($0) }.joined(separator: ", ")
            return "\(template)[\(argsStr)]"
        case .module(let info):
            return "module \(info.modulePath.joined(separator: "."))"
        case .typeVariable(let tv):
            return "?\(tv.id)"
        case .traitObject(let traitName, let typeArgs):
            if typeArgs.isEmpty { return traitName }
            let argsStr = typeArgs.map { getDebugName($0) }.joined(separator: ", ")
            return "[\(argsStr)]\(traitName)"
        }
    }

    // MARK: - Type Variable Queries

    public func freeTypeVariables(in type: Type) -> [TypeVariable] {
        switch type {
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64, .bool, .void, .never:
            return []
        case .typeVariable(let tv):
            return [tv]
        case .function(let params, let returns):
            var result: [TypeVariable] = []
            for param in params {
                result.append(contentsOf: freeTypeVariables(in: param.type))
            }
            result.append(contentsOf: freeTypeVariables(in: returns))
            return result
        case .structure(let defId):
            var result: [TypeVariable] = []
            for member in defIdMap.getStructMembers(defId) ?? [] {
                result.append(contentsOf: freeTypeVariables(in: member.type))
            }
            return result
        case .union(let defId):
            var result: [TypeVariable] = []
            for c in defIdMap.getUnionCases(defId) ?? [] {
                for param in c.parameters {
                    result.append(contentsOf: freeTypeVariables(in: param.type))
                }
            }
            return result
        case .reference(let inner):
            return freeTypeVariables(in: inner)
        case .pointer(let element):
            return freeTypeVariables(in: element)
        case .weakReference(let inner):
            return freeTypeVariables(in: inner)
        case .genericParameter:
            return []
        case .genericStruct(_, let args):
            return args.flatMap { freeTypeVariables(in: $0) }
        case .genericUnion(_, let args):
            return args.flatMap { freeTypeVariables(in: $0) }
        case .module:
            return []
        case .opaque:
            return []
        case .traitObject(_, let typeArgs):
            return typeArgs.flatMap { freeTypeVariables(in: $0) }
        }
    }

    public func containsTypeVariable(_ type: Type) -> Bool {
        return !freeTypeVariables(in: type).isEmpty
    }

    public func getLayoutKey(_ type: Type) -> String {
        switch type {
        case .int: return "I"
        case .int8: return "I8"
        case .int16: return "I16"
        case .int32: return "I32"
        case .int64: return "I64"
        case .uint: return "U"
        case .uint8: return "U8"
        case .uint16: return "U16"
        case .uint32: return "U32"
        case .uint64: return "U64"
        case .float32: return "F32"
        case .float64: return "F64"
        case .bool: return "B"
        case .void: return "V"
        case .never: return "N"
        case .function: return "Fn"
        case .reference(let inner): return "R_\(getLayoutKey(inner))"
        case .pointer(let element): return "P_\(getLayoutKey(element))"
        case .weakReference(let inner): return "W_\(getLayoutKey(inner))"
        case .structure(let defId):
            return layoutKey(for: defId)
        case .union(let defId):
            return layoutKey(for: defId)
        case .opaque(let defId):
            return layoutKey(for: defId)
        case .genericParameter(let name):
            return "Param_\(name)"
        case .genericStruct(let template, let args):
            let argsKeys = args.map { getLayoutKey($0) }.joined(separator: "_")
            return "\(template)_\(argsKeys)"
        case .genericUnion(let template, let args):
            let argsKeys = args.map { getLayoutKey($0) }.joined(separator: "_")
            return "\(template)_\(argsKeys)"
        case .module(let info):
            return "M_\(info.modulePath.joined(separator: "_"))"
        case .typeVariable(let tv):
            return "TV_\(tv.id)"
        case .traitObject(let traitName, let typeArgs):
            if typeArgs.isEmpty { return "TO_\(traitName)" }
            let argsKeys = typeArgs.map { getLayoutKey($0) }.joined(separator: "_")
            return "TO_\(traitName)_\(argsKeys)"
        }
    }

    private func layoutKey(for defId: DefId) -> String {
        guard let metadata = defIdMap.metadata(for: defId) else {
            return "T_\(defId.id)"
        }
        var parts: [String] = []
        if !metadata.modulePath.isEmpty {
            parts.append(metadata.modulePath.joined(separator: "_"))
        }
        if metadata.access == .private {
            var hash: UInt32 = 0
            for char in metadata.sourceFile.utf8 {
                hash = hash &* 31 &+ UInt32(char)
            }
            parts.append("f\(hash % 10000)")
        }
        parts.append(metadata.name)
        if let typeArgs = defIdMap.getTypeArguments(defId), !typeArgs.isEmpty {
            // For generic instantiations, the layout name already includes type args.
            if (defIdMap.isGenericInstantiation(defId) ?? false) == false {
                let argsStr = typeArgs.map { getLayoutKey($0) }.joined(separator: "_")
                parts.append(argsStr)
            }
        }
        return parts.joined(separator: "_")
    }

    public func containsGenericParameter(_ type: Type) -> Bool {
        var visited: Set<DefId> = []
        return containsGenericParameterInternal(type, visited: &visited)
    }

    private func containsGenericParameterInternal(_ type: Type, visited: inout Set<DefId>) -> Bool {
        switch type {
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64, .bool, .void, .never:
            return false
        case .function(let params, let returns):
            return containsGenericParameterInternal(returns, visited: &visited)
                || params.contains { containsGenericParameterInternal($0.type, visited: &visited) }
        case .structure(let defId):
            if let typeArgs = defIdMap.getTypeArguments(defId), !typeArgs.isEmpty {
                return typeArgs.contains { containsGenericParameterInternal($0, visited: &visited) }
            }
            if visited.contains(defId) { return false }
            visited.insert(defId)
            return (defIdMap.getStructMembers(defId) ?? []).contains {
                containsGenericParameterInternal($0.type, visited: &visited)
            }
        case .union(let defId):
            if let typeArgs = defIdMap.getTypeArguments(defId), !typeArgs.isEmpty {
                return typeArgs.contains { containsGenericParameterInternal($0, visited: &visited) }
            }
            if visited.contains(defId) { return false }
            visited.insert(defId)
            return (defIdMap.getUnionCases(defId) ?? []).contains { c in
                c.parameters.contains { containsGenericParameterInternal($0.type, visited: &visited) }
            }
        case .opaque:
            return false
        case .reference(let inner):
            return containsGenericParameterInternal(inner, visited: &visited)
        case .pointer(let element):
            return containsGenericParameterInternal(element, visited: &visited)
        case .weakReference(let inner):
            return containsGenericParameterInternal(inner, visited: &visited)
        case .genericParameter:
            return true
        case .genericStruct(_, let args):
            return args.contains { containsGenericParameterInternal($0, visited: &visited) }
        case .genericUnion(_, let args):
            return args.contains { containsGenericParameterInternal($0, visited: &visited) }
        case .module:
            return false
        case .typeVariable:
            return true
        case .traitObject(_, let typeArgs):
            return typeArgs.contains { containsGenericParameterInternal($0, visited: &visited) }
        }
    }
}