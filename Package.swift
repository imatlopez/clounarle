// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TherapyJournal",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "TherapyJournal",
            path: "Sources/TherapyJournal",
            resources: [
                .process("../../Resources")
            ]
        )
    ]
)
