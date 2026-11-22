load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@bazel_skylib//rules:common_settings.bzl", "bool_flag")

bool_flag(
    name = "mediaLoadingExperimentDefault",
    build_setting_default = False,
    visibility = ["//visibility:public"],
)

config_setting(
    name = "mediaLoadingExperimentEnabled",
    flag_values = {":mediaLoadingExperimentDefault": "True"},
)

swift_library(
    name = "RGSimpleSettings",
    module_name = "RGSimpleSettings",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ] + select({
        ":mediaLoadingExperimentEnabled": ["-DREZA_MEDIA_LOADING_EXPERIMENT"],
        "//conditions:default": [],
    }),
    deps = [
        "//Reza/RGAppGroupIdentifier:RGAppGroupIdentifier",
        "//Reza/RGLogging:RGLogging",
    ],
    visibility = [
        "//visibility:public",
    ],
)
