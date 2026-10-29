// swift-tools-version: 6.0
import PackageDescription

// ทดสอบด้วย swift-testing: เครื่องที่มีแต่ Command Line Tools ต้องรัน ./test.sh แทน `swift test`
let package = Package(
    name: "Jotdown",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown", exact: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "Jotdown",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            path: "Sources/Jotdown",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "JotdownTests",
            dependencies: ["Jotdown"],
            path: "Tests/JotdownTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
