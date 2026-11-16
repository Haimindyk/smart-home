// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "WellnessCore", platforms: [.iOS(.v17)], products: [.library(name: "WellnessCore", targets: ["WellnessCore"])], targets: [.target(name: "WellnessCore"), .testTarget(name: "WellnessCoreTests", dependencies: ["WellnessCore"])])
