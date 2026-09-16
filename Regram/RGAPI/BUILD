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
        "//Regram/RGLogging:RGLogging",
        "//Regram/RGWebAppExtensions:RGWebAppExtensions",
        "//Regram/RGSimpleSettings:RGSimpleSettings",
        "//Regram/RGWebSettingsScheme:RGWebSettingsScheme",
        "//Regram/RGRegDateScheme:RGRegDateScheme",
        "//Regram/RGRequests:RGRequests",
        "//Regram/RGConfig:RGConfig"
    ],
    visibility = [
        "//visibility:public",
    ],
)
