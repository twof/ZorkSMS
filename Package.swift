// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "ZorkSMS",
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "3.2.0"),

        // 🔵 Swift ORM (queries, models, relations, etc) built on SQLite 3.
        .package(url: "https://github.com/vapor/fluent-sqlite.git", from: "3.0.0"),
        .package(url: "https://github.com/twof/VaporTwilioService.git", .branch("feature/longResponse")),
        
        .package(url: "https://github.com/JohnSundell/Files.git", from: "2.2.1")
        
    ],
    targets: [
        .target(name: "App", dependencies: ["FluentSQLite", "Vapor", "Twilio", "Files"]),
        .target(name: "Run", dependencies: ["App"]),
        .testTarget(name: "AppTests", dependencies: ["App"])
    ]
)

