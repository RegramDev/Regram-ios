load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_configuration//:variables.bzl", "telegram_bundle_id")
load("//build-system/bazel-utils:beta_identity.bzl", "require_beta_bundle_id")

require_beta_bundle_id(telegram_bundle_id)

swift_library(
    name = "RGAppGroupIdentifier",
    module_name = "RGAppGroupIdentifier",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
    ],
    visibility = [
        "//visibility:public",
    ],
)
