load("@bazel_skylib//rules:common_settings.bzl", "bool_flag")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

bool_flag(
    name = "sandboxOnly",
    build_setting_default = False,
    visibility = ["//visibility:public"],
)

config_setting(
    name = "sandboxOnlySetting",
    flag_values = {
        ":sandboxOnly": "True",
    },
    visibility = ["//visibility:public"],
)

swift_library(
    name = "RGAppGroupIdentifier",
    module_name = "RGAppGroupIdentifier",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ] + select({
        ":sandboxOnlySetting": ["-DREGRAM_SANDBOX_ONLY"],
        "//conditions:default": [],
    }),
    deps = [
    ],
    visibility = [
        "//visibility:public",
    ],
)
