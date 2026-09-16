load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGSwiftUI",
    module_name = "RGSwiftUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        # "-warnings-as-errors",
    ],
    deps = [
        "//submodules/LegacyUI:LegacyUI",
        "//submodules/Display:Display",
        "//submodules/TelegramPresentationData:TelegramPresentationData"
    ],
    visibility = [
        "//visibility:public",
    ],
)
