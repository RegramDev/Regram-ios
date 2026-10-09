load("@rules_cc//cc:objc_library.bzl", "objc_library") # MARK: Regram — Bazel 9 removes native objc_library.

objc_library(
    name = "RGCloudKitGuard",
    module_name = "RGCloudKitGuard",
    enable_modules = True,
    srcs = glob([
        "Sources/*.m",
    ]),
    copts = [
        "-Werror",
    ],
    hdrs = glob([
        "PublicHeaders/**/*.h",
    ]),
    includes = [
        "PublicHeaders",
    ],
    sdk_frameworks = [
        "CloudKit",
    ],
    deps = [
    ],
    visibility = ["//visibility:public"],
)
