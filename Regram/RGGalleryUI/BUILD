load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGGalleryUI",
    module_name = "RGGalleryUI",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = ["//submodules/ComponentFlow", "//submodules/Display:Display"],
    visibility = ["//visibility:public"],
)
