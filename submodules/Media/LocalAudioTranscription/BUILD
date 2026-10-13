# MARK: Regram — Regram source and dependency names.
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

rgdeps = [
    "//Regram/RGLogging:RGLogging"
]

swift_library(
    name = "LocalAudioTranscription",
    module_name = "LocalAudioTranscription",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = rgdeps +[
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)
