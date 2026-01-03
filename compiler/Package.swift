// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "koralc",
  products: [
    // Products define the executables and libraries a package produces, making them visible to other packages.
    .executable(
      name: "koralc",
      targets: ["koralc"]),
    .library(
      name: "KoralCompiler",
      targets: ["KoralCompiler"])
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .target(
      name: "KoralCompiler",
      path: "Sources/KoralCompiler"
    ),
    .executableTarget(
      name: "koralc",
      dependencies: ["KoralCompiler"],
      path: "Sources/koralc"
    ),
    .testTarget(
      name: "koralcTests",
      dependencies: ["KoralCompiler"]
    ),
  ]
)
