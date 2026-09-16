load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGLoggingComposer",
    module_name = "RGLoggingComposer",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Regram/RGLogging:RGLogging",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)