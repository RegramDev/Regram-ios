# MARK: Regram — Regram source and dependency names.
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

rgsrc = [
    "//Regram/RGSwiftSignalKit:RGSwiftSignalKit"
]

swift_library(
    name = "SwiftSignalKit",
    module_name = "SwiftSignalKit",
    srcs = rgsrc + glob([
        "Source/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    visibility = [
        "//visibility:public",
    ],
)
