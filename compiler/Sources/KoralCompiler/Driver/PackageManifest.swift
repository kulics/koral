import Foundation

// MARK: - Manifest errors
//
// The manifest names a package and the modules inside it. Everything about
// WHERE a package comes from lives in the consumer's `dependencies` (§5.3) --
// a package never declares its own `source`, so the same package can sit at
// different places for different consumers without either side being wrong.

public enum PackageManifestError: Error, CustomStringConvertible {
  case fileNotFound(String)
  case invalidJSON(String)
  case invalidField(path: String, message: String)
  case missingTargetModule(String)
  /// A driver-level failure that is not about the manifest's shape.
  case message(String)
  case duplicateModuleEntry(String)
  case unknownPackageName(name: String, context: String, known: [String])
  case unknownModule(name: String, packageName: String, declared: [String])
  case noMainModule(packageName: String, declared: [String])
  case duplicatePackageName(name: String)
  case duplicateDependencySource(source: String, first: String, second: String)
  case reservedName(name: String)
  case cyclicModuleDependency([String])
  case unsupportedSource(source: String)

  public var description: String {
    switch self {
    case .fileNotFound(let path):
      return "Manifest file not found: \(path)"
    case .invalidJSON(let path):
      return "Invalid manifest JSON: \(path)"
    case .invalidField(let path, let message):
      return "Invalid manifest field '\(path)': \(message)"
    case .missingTargetModule(let module):
      return "Target module '\(module)' not found in resolved module graph"
    case .message(let text):
      return text
    case .duplicateModuleEntry(let entry):
      return "entry file '\(entry)' is declared by two modules"
    case .unknownPackageName(let name, let context, let known):
      let knownList = known.sorted().joined(separator: ", ")
      return "Unknown package name \"\(name)\"\n  referenced from \(context)\n  known package names: \(knownList)"
    case .unknownModule(let name, let packageName, let declared):
      // One condition, one spelling: the `using` path reports these through
      // `ModuleError`, and the two must not grow apart.
      let declaredList = declared.isEmpty ? "<none>" : declared.sorted().joined(separator: ", ")
      return "Module '\(name)' does not exist in package '\(packageName)'; declared modules: \(declaredList)"
    case .noMainModule(let packageName, let declared):
      let declaredList = declared.isEmpty ? "<none>" : declared.sorted().joined(separator: ", ")
      return "Package '\(packageName)' has no main module; write its subpath instead; declared modules: \(declaredList)"
    case .duplicatePackageName(let name):
      return "Package name '\(name)' is registered twice"
    case .duplicateDependencySource(let source, let first, let second):
      return "Source '\(source)' is declared by both '\(first)' and '\(second)'; one package would have two spellings"
    case .reservedName(let name):
      return "Package name '\(name)' is reserved"
    case .cyclicModuleDependency(let cycle):
      return "Cyclic module dependency: \(cycle.joined(separator: " -> "))"
    case .unsupportedSource(let source):
      return "Cannot locate package source '\(source)'\n  only 'path:' sources are resolvable without a fetch step"
    }
  }
}

// MARK: - Manifest shape
//
// Four fields (§5.1): `package`, `version`, `modules`, `dependencies`.
// No `name` (it is the same thing as `package`), no top-level `entry` (the
// default build target IS the main module), no `requires` (the module graph
// comes from `using`, §5.4), no `module_aliases` (renaming is the dependency
// key, §5.3).

public struct PackageDependencyConfig {
  /// The name this package writes when it refers to the dependency.
  public let key: String
  /// Pure fetch location, and the package's identity. Never contains a ref.
  public let source: String
  /// Semver constraint. The exact version is a lockfile's job (§5.5) and is
  /// not consulted here.
  public let version: String
}

public struct PackageModuleConfig {
  /// The name as written in the manifest: `"."` for the main module, otherwise
  /// the sub-path (`"io"`, `"compiler/parser"`). This is the package-internal
  /// name -- a consumer spells the FULL name, `package[/subpath]`.
  public let key: String
  /// Sub-path inside the package; empty for the main module.
  public let subpath: String
  /// Entry file, absolute. Relative to the package root as declared.
  public let entryPath: String
  public let links: [String]
}

public struct PackageManifest {
  public let manifestPath: String
  public let packageRoot: String
  /// This package's own name. What its own source writes, and the default name
  /// a consumer uses. It is NOT identity -- identity is `source` (§5.3).
  public let packageName: String
  public let version: String
  /// Keyed by the package-internal module name (`"."`, `"io"`, `"compiler/parser"`).
  public let modules: [String: PackageModuleConfig]
  /// Keyed by the source name this package writes for each dependency.
  public let dependencies: [String: PackageDependencyConfig]
}

public enum ResolvedPackageKind {
  case root
  case std
  case dependency(key: String)
}

// MARK: - Loaded packages
//
// A package is reached by a NAME, and that name is whoever is asking (§4):
// `dep_utils` writes `using "dep_utils/…"`, its consumer writes
// `using "game_utils/…"`. Both land on the same package because each package
// resolves its own source with its own table. The package's identity is its
// `source`, which is what the two spellings have in common.

public final class LoadedPackage {
  /// Identity. `source` for dependencies, the package name for the root,
  /// `"std"` for the built-in standard library.
  public let identity: String
  /// What this package's OWN source writes for itself (`manifest.package`).
  public let selfName: String
  public let manifest: PackageManifest
  public let kind: ResolvedPackageKind

  public init(identity: String, selfName: String, manifest: PackageManifest, kind: ResolvedPackageKind) {
    self.identity = identity
    self.selfName = selfName
    self.manifest = manifest
    self.kind = kind
  }
}

/// The set of packages in a compile, plus the rule for turning a name written
/// in some package's source into a package.
public final class PackageRegistry {
  private var byIdentity: [String: LoadedPackage] = [:]
  public private(set) var all: [LoadedPackage] = []

  public var stdPackage: LoadedPackage?
  /// The package the build was invoked on -- the one whose manifest named the
  /// build. Distinct from `stdPackage` even when they are the same package.
  public var rootPackage: LoadedPackage?

  public func register(_ package: LoadedPackage) {
    if byIdentity[package.identity] == nil {
      byIdentity[package.identity] = package
      all.append(package)
    }
    if case .std = package.kind {
      stdPackage = package
    }
    if case .root = package.kind {
      rootPackage = package
    }
  }

  public func package(identity: String) -> LoadedPackage? {
    byIdentity[identity]
  }

  /// Resolve `name` as written in `owner`'s source.
  ///
  /// A package name is one of three things (§4): the package's own `package`,
  /// one of its `dependencies` keys, or the reserved `std`. Nothing else.
  public func resolveName(_ name: String, from owner: LoadedPackage) -> LoadedPackage? {
    if name == owner.selfName {
      return owner
    }
    if let dependency = owner.manifest.dependencies[name] {
      return byIdentity[dependency.source]
    }
    if name == "std" {
      return stdPackage
    }
    return nil
  }

  /// Every name `owner` can write, for error messages.
  public func knownNames(for owner: LoadedPackage) -> [String] {
    var names = [owner.selfName, "std"]
    names.append(contentsOf: owner.manifest.dependencies.keys)
    return names
  }
}

// MARK: - Resolved module

/// A module as the rest of the compiler sees it.
public struct ResolvedModuleSpec {
  /// The full name as written from the ROOT package's point of view:
  /// `package[/subpath]`. Display only -- identity is `(package identity, subpath)`.
  public let fullName: String
  /// Full name split into identifier segments. Used to qualify top-level
  /// symbols; see §10.4 for why this is still name-based and open.
  public let pathSegments: [String]
  /// Package-internal module name: `"."` for the main module, else the subpath.
  public let key: String
  /// Subpath inside the package; empty for the main module.
  public let subpath: String
  public let entryFile: String
  public let links: [String]
  public let packageIdentity: String
  public let packageKind: ResolvedPackageKind
  /// The package that owns this module. Resolution of this module's own
  /// `using` statements goes through its table, not the root's.
  public let owner: LoadedPackage
}

/// Build a module spec from a manifest entry.
public func makeResolvedModuleSpec(
  key: String,
  config: PackageModuleConfig,
  rootName: String,
  owner: LoadedPackage
) -> ResolvedModuleSpec {
  let fullName = config.subpath.isEmpty ? rootName : "\(rootName)/\(config.subpath)"
  var segments = [moduleFileNameToIdentifier(rootName)]
  if !config.subpath.isEmpty {
    segments.append(contentsOf: config.subpath.split(separator: "/").map {
      moduleFileNameToIdentifier(String($0))
    })
  }
  return ResolvedModuleSpec(
    fullName: fullName,
    pathSegments: segments,
    key: key,
    subpath: config.subpath,
    entryFile: config.entryPath,
    links: config.links,
    packageIdentity: owner.identity,
    packageKind: owner.kind,
    owner: owner
  )
}

// MARK: - Parsing

private func isIdentifierSegment(_ segment: String) -> Bool {
  guard let first = segment.first, first.isASCII, first.isLowercase else {
    return false
  }
  for ch in segment {
    guard ch.isASCII else { return false }
    if ch.isLowercase || ch.isNumber || ch == "_" { continue }
    return false
  }
  return true
}

/// A package name is a single identifier segment (§2.1) -- no `/`, no `.`.
public func isValidPackageOrSegmentName(_ name: String) -> Bool {
  !name.isEmpty && isIdentifierSegment(name)
}

/// A manifest module key is `"."` or a `/`-separated subpath of identifier
/// segments (§5.2). It never carries the package name -- that would be
/// describing the package from the outside, which is the consumer's job.
///
/// Returns the subpath: `""` for the main module, otherwise the key itself.
/// `nil` means the key is not a legal module key at all.
public func parseManifestModuleKey(_ key: String) -> String? {
  if key == "." {
    return ""
  }
  guard !key.isEmpty, !key.contains(".") else {
    return nil
  }
  // `split` drops empty segments, so `io` and `io/` would both become `io` and
  // two keys would name one module. Reject the empty ones outright.
  guard !key.hasPrefix("/"), !key.hasSuffix("/"), !key.contains("//") else {
    return nil
  }
  let parts = key.split(separator: "/").map(String.init)
  guard !parts.isEmpty else { return nil }
  for part in parts where !isValidPackageOrSegmentName(part) {
    return nil
  }
  return key
}

/// A semver constraint (§5.3): an optional comparison operator followed by a
/// dotted numeric version. The exact version is a lockfile's job -- this only
/// says the constraint is written in a form that means something.
public func isValidVersionConstraint(_ text: String) -> Bool {
  var rest = Substring(text)
  for op in ["^", "~", ">=", "<=", ">", "<", "="] {
    if rest.hasPrefix(op) {
      rest = rest.dropFirst(op.count)
      break
    }
  }
  let parts = rest.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
  guard parts.count >= 2, parts.count <= 4 else { return false }
  for part in parts {
    guard !part.isEmpty, part.allSatisfy({ $0.isNumber }) else { return false }
  }
  return true
}

private func expectObject(_ value: Any, path: String) throws -> [String: Any] {
  guard let object = value as? [String: Any] else {
    throw PackageManifestError.invalidField(path: path, message: "expected object")
  }
  return object
}

private func expectString(_ value: Any?, path: String) throws -> String {
  guard let value else {
    throw PackageManifestError.invalidField(path: path, message: "missing required string")
  }
  guard let string = value as? String else {
    throw PackageManifestError.invalidField(path: path, message: "expected string")
  }
  return string
}

private func optionalString(_ value: Any?, path: String) throws -> String? {
  guard let value else { return nil }
  guard let string = value as? String else {
    throw PackageManifestError.invalidField(path: path, message: "expected string")
  }
  return string
}

private func optionalStringArray(_ value: Any?, path: String) throws -> [String] {
  guard let value else { return [] }
  guard let array = value as? [Any] else {
    throw PackageManifestError.invalidField(path: path, message: "expected string array")
  }
  var result: [String] = []
  for (index, element) in array.enumerated() {
    guard let string = element as? String else {
      throw PackageManifestError.invalidField(
        path: "\(path)[\(index)]",
        message: "expected string"
      )
    }
    result.append(string)
  }
  return result
}

public func loadPackageManifest(at manifestPath: String) throws -> PackageManifest {
  let manifestURL = URL(fileURLWithPath: manifestPath).standardized
  guard FileManager.default.fileExists(atPath: manifestURL.path) else {
    throw PackageManifestError.fileNotFound(manifestURL.path)
  }

  let data = try Data(contentsOf: manifestURL)
  let raw: Any
  do {
    raw = try JSONSerialization.jsonObject(with: data)
  } catch {
    throw PackageManifestError.invalidJSON(manifestURL.path)
  }

  let object = try expectObject(raw, path: "<root>")
  let packageRoot = manifestURL.deletingLastPathComponent().path

  let packageName = try expectString(object["package"], path: "package")
  guard isValidPackageOrSegmentName(packageName) else {
    throw PackageManifestError.invalidField(
      path: "package",
      message: "package name must be a single lowercase identifier"
    )
  }

  let version = try expectString(object["version"], path: "version")

  // `name` / `entry` / `requires` / `module_aliases` are gone (§5.1). Their
  // absence is the point, so a manifest that still carries one is told so
  // instead of being silently half-read.
  for obsolete in ["name", "entry", "requires", "module_aliases", "links"] where object[obsolete] != nil {
    throw PackageManifestError.invalidField(
      path: obsolete,
      message: obsoleteFieldHint(obsolete)
    )
  }
  if let rawModules = object["modules"] as? [String: Any] {
    for (moduleName, rawModule) in rawModules {
      let moduleObject = (rawModule as? [String: Any]) ?? [:]
      for obsolete in ["requires"] where moduleObject[obsolete] != nil {
        throw PackageManifestError.invalidField(
          path: "modules.\(moduleName).\(obsolete)",
          message: obsoleteFieldHint(obsolete)
        )
      }
    }
  }

  var dependencies: [String: PackageDependencyConfig] = [:]
  if let rawDependencies = object["dependencies"] {
    let dependencyObject = try expectObject(rawDependencies, path: "dependencies")
    var sourceOwners: [String: String] = [:]
    // Sorted: the message names the two keys that fight, and which one is
    // "first" must not depend on hash iteration order.
    for depKey in dependencyObject.keys.sorted() {
      guard let rawDependency = dependencyObject[depKey] else { continue }
      guard isValidPackageOrSegmentName(depKey) else {
        throw PackageManifestError.invalidField(
          path: "dependencies.\(depKey)",
          message: "dependency key must be a single lowercase identifier"
        )
      }
      if depKey == packageName {
        throw PackageManifestError.invalidField(
          path: "dependencies.\(depKey)",
          message: "dependency key collides with this package's own name"
        )
      }
      if depKey == "std" {
        throw PackageManifestError.reservedName(name: depKey)
      }
      let depObject = try expectObject(rawDependency, path: "dependencies.\(depKey)")
      let source = try expectString(depObject["source"], path: "dependencies.\(depKey).source")
      let depVersion = try expectString(depObject["version"], path: "dependencies.\(depKey).version")
      guard isValidVersionConstraint(depVersion) else {
        throw PackageManifestError.invalidField(
          path: "dependencies.\(depKey).version",
          message: "'\(depVersion)' is not a semver constraint (for example '^1.2')"
        )
      }
      if source.contains("#") || source.contains("?") {
        throw PackageManifestError.invalidField(
          path: "dependencies.\(depKey).source",
          message: "source must not carry a ref; pin the version with koral.lock"
        )
      }
      if let previous = sourceOwners[source] {
        // One source may only have one spelling in a project (§4). Name both
        // keys so the reader can see which two are fighting.
        throw PackageManifestError.duplicateDependencySource(
          source: source,
          first: previous,
          second: depKey
        )
      }
      sourceOwners[source] = depKey
      dependencies[depKey] = PackageDependencyConfig(
        key: depKey,
        source: source,
        version: depVersion
      )
    }
  }

  guard let rawModules = object["modules"] else {
    throw PackageManifestError.invalidField(path: "modules", message: "missing required object")
  }
  let moduleObject = try expectObject(rawModules, path: "modules")
  var modules: [String: PackageModuleConfig] = [:]
  var seenEntries = Set<String>()
  for (moduleName, rawModule) in moduleObject {
    guard let subpath = parseManifestModuleKey(moduleName) else {
      throw PackageManifestError.invalidField(
        path: "modules.\(moduleName)",
        message: "module key must be '.' or lowercase segments joined by '/'"
      )
    }
    let moduleConfigObject = try expectObject(rawModule, path: "modules.\(moduleName)")
    let entryPath = try expectString(moduleConfigObject["entry"], path: "modules.\(moduleName).entry")
    let absoluteEntry = URL(fileURLWithPath: packageRoot)
      .appendingPathComponent(entryPath)
      .standardized
      .path
    if !seenEntries.insert(absoluteEntry).inserted {
      throw PackageManifestError.duplicateModuleEntry(entryPath)
    }
    // An entry file lives inside the package (§7.16). `entry` is relative to
    // the package root, so a path that climbs out is either a mistake or an
    // attempt to compile someone else's source under this package's name.
    let rootPath = URL(fileURLWithPath: packageRoot).standardized.path
    guard absoluteEntry == rootPath || absoluteEntry.hasPrefix(rootPath + "/") else {
      throw PackageManifestError.invalidField(
        path: "modules.\(moduleName).entry",
        message: "entry file '\(entryPath)' is outside the package root"
      )
    }
    guard FileManager.default.fileExists(atPath: absoluteEntry) else {
      throw PackageManifestError.invalidField(
        path: "modules.\(moduleName).entry",
        message: "entry file '\(entryPath)' does not exist"
      )
    }
    let links = try optionalStringArray(moduleConfigObject["links"], path: "modules.\(moduleName).links")
    modules[moduleName] = PackageModuleConfig(
      key: moduleName,
      subpath: subpath,
      entryPath: absoluteEntry,
      links: links
    )
  }

  if modules.isEmpty {
    throw PackageManifestError.invalidField(path: "modules", message: "a package declares at least one module")
  }

  return PackageManifest(
    manifestPath: manifestURL.path,
    packageRoot: packageRoot,
    packageName: packageName,
    version: version,
    modules: modules,
    dependencies: dependencies
  )
}

private func obsoleteFieldHint(_ field: String) -> String {
  switch field {
  case "name":
    return "renamed to 'package'; 'package' is the name the SOURCE writes, not an identity"
  case "entry":
    return "removed; the default build target is the main module ('modules' key \".\")"
  case "requires":
    return "removed; the module graph is derived from 'using' (§5.4)"
  case "module_aliases":
    return "removed; renaming a dependency is its 'dependencies' key (§5.3)"
  case "links":
    return "moved onto the module that needs it ('modules.<key>.links')"
  default:
    return "unsupported"
  }
}

// MARK: - Loading the package set
//
// `path:` sources are relative to the manifest that declares them (§5.3), so a
// dependency can say `path:../slug` and mean the same directory from anywhere
// that dependency is reused. Anything else is a fetch location: `koral get`
// materializes it and the compiler reads it back from the cache.

public func locateDependency(
  _ dependency: PackageDependencyConfig,
  declaringManifest: PackageManifest,
  fetchRoot: String?
) throws -> String {
  if dependency.source.hasPrefix("path:") {
    let relative = String(dependency.source.dropFirst("path:".count))
    guard !relative.isEmpty else {
      throw PackageManifestError.invalidField(
        path: "dependencies.\(dependency.key).source",
        message: "'path:' source needs a path after the colon"
      )
    }
    return URL(fileURLWithPath: declaringManifest.packageRoot)
      .appendingPathComponent(relative)
      .appendingPathComponent("koral.json")
      .standardized
      .path
  }

  guard let fetchRoot else {
    throw PackageManifestError.unsupportedSource(source: dependency.source)
  }
  return URL(fileURLWithPath: fetchRoot)
    .appendingPathComponent(dependency.key)
    .appendingPathComponent("koral.json")
    .standardized
    .path
}

/// Load the root package and every package reachable from it, transitively.
public func loadPackageRegistry(
  rootManifestPath: String,
  stdManifestPath: String?,
  fetchRoot: String?
) throws -> PackageRegistry {
  let registry = PackageRegistry()
  let rootManifest = try loadPackageManifest(at: rootManifestPath)

  // Building the standard library itself makes the root package BE std: one
  // package, one identity, and it is the prelude for everyone else.
  let rootIsStd = stdManifestPath.map {
    URL(fileURLWithPath: $0).standardized.path == URL(fileURLWithPath: rootManifestPath).standardized.path
  } ?? false

  let root: LoadedPackage
  if rootIsStd {
    root = LoadedPackage(
      identity: "std",
      selfName: "std",
      manifest: rootManifest,
      kind: .std
    )
    registry.rootPackage = root
  } else {
    if rootManifest.packageName == "std" {
      throw PackageManifestError.reservedName(name: rootManifest.packageName)
    }
    root = LoadedPackage(
      identity: rootManifest.packageName,
      selfName: rootManifest.packageName,
      manifest: rootManifest,
      kind: .root
    )
    registry.rootPackage = root
    if let stdManifestPath {
      let stdManifest = try loadPackageManifest(at: stdManifestPath)
      let std = LoadedPackage(
        identity: "std",
        selfName: "std",
        manifest: stdManifest,
        kind: .std
      )
      registry.register(std)
    }
  }
  registry.register(root)

  // Breadth-first so a package is loaded once no matter how many others name it.
  var pending: [LoadedPackage] = [root]
  if let std = registry.stdPackage {
    pending.append(std)
  }
  var next = 0
  while next < pending.count {
    let owner = pending[next]
    next += 1
    for dependency in owner.manifest.dependencies.values.sorted(by: { $0.key < $1.key }) {
      if registry.package(identity: dependency.source) != nil {
        continue
      }
      let manifestPath = try locateDependency(
        dependency,
        declaringManifest: owner.manifest,
        fetchRoot: fetchRoot
      )
      let manifest: PackageManifest
      do {
        manifest = try loadPackageManifest(at: manifestPath)
      } catch {
        throw PackageManifestError.invalidField(
          path: "dependencies.\(dependency.key).source",
          message: "cannot load '\(dependency.source)': \(error)"
        )
      }
      // `std` is reserved (§7.20). Only the standard library's own manifest
      // may claim it; a dependency trying to is a name collision with the
      // built-in, not a package that happens to share its name.
      if manifest.packageName == "std" {
        throw PackageManifestError.reservedName(name: manifest.packageName)
      }
      let package = LoadedPackage(
        identity: dependency.source,
        selfName: manifest.packageName,
        manifest: manifest,
        kind: .dependency(key: dependency.key)
      )
      registry.register(package)
      pending.append(package)
    }
  }

  // Two names for one package is the thing that would let the same module be
  // spelled two ways inside one project -- catch it at load time (§4).
  var nameOwners: [String: String] = [:]
  for package in registry.all {
    var names = [package.selfName]
    names.append(contentsOf: package.manifest.dependencies.keys)
    for name in names {
      if let previous = nameOwners[name], previous != package.identity {
        // The same name is claimed by two packages in two different resolution
        // contexts. That is legal: each package resolves with its own table.
        continue
      }
      nameOwners[name] = package.identity
    }
  }

  return registry
}

/// All modules a package declares, as resolved specs, keyed by root-view name.
public func modulesOfPackage(
  _ package: LoadedPackage,
  rootName: String
) -> [String: ResolvedModuleSpec] {
  var result: [String: ResolvedModuleSpec] = [:]
  for (key, config) in package.manifest.modules {
    let spec = makeResolvedModuleSpec(key: key, config: config, rootName: rootName, owner: package)
    result[spec.fullName] = spec
  }
  return result
}

/// The name the ROOT package uses for `package`. For the root itself that is
/// its own `package`; for a dependency it is the root's `dependencies` key;
/// for std it is `"std"`.
public func rootViewName(of package: LoadedPackage, registry: PackageRegistry, root: LoadedPackage) -> String {
  switch package.kind {
  case .root, .std:
    return package.selfName
  case .dependency:
    for (key, dependency) in root.manifest.dependencies where dependency.source == package.identity {
      return key
    }
    return package.selfName
  }
}
