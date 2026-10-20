load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
swift_library(
    name = "RGFeatureSignals", module_name = "RGFeatureSignals", srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = ["//Regram/RGSimpleSettings", "//submodules/SSignalKit/SwiftSignalKit"],
    visibility = ["//visibility:public"],
)
