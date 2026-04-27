import ProjectDescription

let project = Project(
    name: "Baseline",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0"
        ]
    ),
    targets: [
        .target(
            name: "Baseline",
            destinations: .macOS,
            product: .app,
            bundleId: "com.arshia.baseline",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .extendingDefault(
                with: [
                    "CFBundleDisplayName": "Baseline",
                    "LSApplicationCategoryType": "public.app-category.utilities",
                    "LSUIElement": true
                ]
            ),
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            dependencies: []
        ),
        .target(
            name: "BaselineTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.arshia.baseline.tests",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .default,
            sources: ["Tests/**/*.swift"],
            resources: ["Tests/Fixtures/**"],
            dependencies: [.target(name: "Baseline")]
        )
    ]
)
