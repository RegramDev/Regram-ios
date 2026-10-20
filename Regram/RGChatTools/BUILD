load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGChatTools",
    module_name = "RGChatTools",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//Regram/RGStrings:RGStrings",
        "//submodules/ComponentFlow",
        "//submodules/Display",
        "//submodules/TelegramPresentationData",
    ],
    visibility = ["//visibility:public"],
)
