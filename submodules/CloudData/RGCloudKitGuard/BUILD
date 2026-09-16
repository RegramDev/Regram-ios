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
