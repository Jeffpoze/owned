// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "text_reader",
    platforms: [.iOS("15.0")],
    products: [.library(name: "text-reader", targets: ["text_reader"])],
    dependencies: [],
    targets: [.target(name: "text_reader", dependencies: [])]
)
