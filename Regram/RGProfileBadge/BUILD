load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
swift_library(
    name = "RGProfileBadge",
    module_name = "RGProfileBadge",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = ["//submodules/Display:Display", "//Regram/RGStrings:RGStrings"],
    visibility = ["//visibility:public"],
)
