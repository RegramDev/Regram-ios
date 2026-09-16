load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGLogging",
    module_name = "RGLogging",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/ManagedFile:ManagedFile",
        "//Regram/RGAppGroupIdentifier:RGAppGroupIdentifier",
    ],
    visibility = [
        "//visibility:public",
    ],
)
