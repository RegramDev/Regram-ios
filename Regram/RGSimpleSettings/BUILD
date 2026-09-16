load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGSimpleSettings",
    module_name = "RGSimpleSettings",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Regram/RGAppGroupIdentifier:RGAppGroupIdentifier",
        "//Regram/RGLogging:RGLogging",
    ],
    visibility = [
        "//visibility:public",
    ],
)
