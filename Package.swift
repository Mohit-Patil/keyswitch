// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KeySwitch",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "keyswitch-prototype", targets: ["KeySwitchPrototype"]),
    ],
    targets: [
        .executableTarget(
            name: "KeySwitchPrototype",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
