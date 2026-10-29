// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoteToIssue",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NoteToIssueCore", targets: ["NoteToIssueCore"]),
        .executable(name: "NoteToIssue", targets: ["NoteToIssue"])
    ],
    targets: [
        .target(name: "NoteToIssueCore", resources: [.copy("Resources")]),
        .executableTarget(name: "NoteToIssue", dependencies: ["NoteToIssueCore"]),
        .testTarget(name: "NoteToIssueCoreTests", dependencies: ["NoteToIssueCore"]),
        .testTarget(name: "NoteToIssueAppTests", dependencies: ["NoteToIssue"])
    ]
)
