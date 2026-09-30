// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XiaoXiaoXin",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "XiaoXiaoXin",
            exclude: ["Resources"],
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ]
)
