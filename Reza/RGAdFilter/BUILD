load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

filegroup(
    name = "ModelResources",
    srcs = glob(["Resources/*"]),
    visibility = ["//visibility:public"],
)

swift_library(
    name = "RGAdFilter",
    module_name = "RGAdFilter",
    srcs = glob(["Sources/*.swift"]),
    copts = ["-warnings-as-errors"],
    visibility = ["//visibility:public"],
)
