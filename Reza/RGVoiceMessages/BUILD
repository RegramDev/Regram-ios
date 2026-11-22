load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGVoiceMessages",
    module_name = "RGVoiceMessages",
    srcs = glob(["Sources/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//submodules/FFMpegBinding",
        "//submodules/OpusBinding",
    ],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "ChatVoiceImport",
    srcs = glob(["TelegramUI/*.swift"]),
    visibility = ["//visibility:public"],
)
