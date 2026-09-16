load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGGHSettings",
    module_name = "RGGHSettings",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Regram/RGGHSettingsScheme:RGGHSettingsScheme",
        "//Regram/RGLogging:RGLogging",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramCore:TelegramCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)