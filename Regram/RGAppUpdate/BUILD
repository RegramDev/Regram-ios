load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGAppUpdate",
    module_name = "RGAppUpdate",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = ["//Regram/RGUpdateActivity", "//Regram/RGStrings", "//Regram/RGUpdateSigner:RGUpdateSigner", "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit"],
    visibility = ["//visibility:public"],
)
