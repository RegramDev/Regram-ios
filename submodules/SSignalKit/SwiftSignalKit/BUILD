load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

sgsrc = [
    "//Regram/RGSwiftSignalKit:RGSwiftSignalKit"
]

swift_library(
    name = "SwiftSignalKit",
    module_name = "SwiftSignalKit",
    srcs = sgsrc + glob([
        "Source/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    visibility = [
        "//visibility:public",
    ],
)
