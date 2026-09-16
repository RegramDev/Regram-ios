load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGAPIToken",
    module_name = "RGAPIToken",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramCore:TelegramCore",
        "//Regram/RGLogging:RGLogging",
        "//Regram/RGWebSettingsScheme:RGWebSettingsScheme",
        "//Regram/RGConfig:RGConfig",
        "//Regram/RGWebAppExtensions:RGWebAppExtensions",
    ],
    visibility = [
        "//visibility:public",
    ],
)
