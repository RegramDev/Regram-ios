load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGAPIWebSettings",
    module_name = "RGAPIWebSettings",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Regram/RGAPI:RGAPI",
        "//Regram/RGAPIToken:RGAPIToken",
        "//Regram/RGLogging:RGLogging",
        "//Regram/RGSimpleSettings:RGSimpleSettings",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramCore:TelegramCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
