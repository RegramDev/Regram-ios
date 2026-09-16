load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

filegroup(
    name = "RGPayWallAssets",
    srcs = glob(["Images.xcassets/**"]),
    visibility = ["//visibility:public"],
)

swift_library(
    name = "RGPayWall",
    module_name = "RGPayWall",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Regram/RGIAP:RGIAP",
        "//Regram/RGLogging:RGLogging",
        "//Regram/RGSimpleSettings:RGSimpleSettings",
        "//Regram/RGSwiftUI:RGSwiftUI",
        "//Regram/RGStrings:RGStrings",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)
