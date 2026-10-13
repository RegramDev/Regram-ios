load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGWebTranslation",
    module_name = "RGWebTranslation",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//submodules/AccountContext",
        "//submodules/TelegramCore",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//Regram/RGStrings",
        "//Regram/RGSimpleSettings",
        "//submodules/TranslateUI",
    ],
    visibility = ["//visibility:public"],
)
