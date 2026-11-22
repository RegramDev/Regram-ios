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
        "//Reza/RGGHSettingsScheme:RGGHSettingsScheme",
        "//Reza/RGLogging:RGLogging",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramCore:TelegramCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)