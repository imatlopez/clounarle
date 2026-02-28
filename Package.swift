// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TherapyJournal",
    platforms: [
        .macOS(.v26)
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
