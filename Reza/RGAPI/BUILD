load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGAPI",
    module_name = "RGAPI",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//Reza/RGLogging:RGLogging",
        "//Reza/RGWebAppExtensions:RGWebAppExtensions",
        "//Reza/RGSimpleSettings:RGSimpleSettings",
        "//Reza/RGWebSettingsScheme:RGWebSettingsScheme",
        "//Reza/RGRegDateScheme:RGRegDateScheme",
        "//Reza/RGRequests:RGRequests",
        "//Reza/RGConfig:RGConfig"
    ],
    visibility = [
        "//visibility:public",
    ],
)
