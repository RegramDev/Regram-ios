load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGGTranslate",
    module_name = "RGGTranslate",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//Regram/SwiftSoup:SwiftSoup",
    ],
    visibility = [
        "//visibility:public",
    ],
)
