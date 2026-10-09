load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

filegroup(
    name = "Fonts",
    srcs = glob(["Fonts/*.ttf", "Licenses/*.txt"]),
    visibility = ["//visibility:public"],
)

swift_library(
    name = "RGTypography",
    module_name = "RGTypography",
    srcs = glob(["Sources/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = ["//Regram/RGSimpleSettings:RGSimpleSettings", "//submodules/AppBundle:AppBundle"],
    visibility = ["//visibility:public"],
)

load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

swift_library(
    name = "TypographyTestHostLib",
    testonly = True,
    srcs = ["Tests/Host.swift"],
    data = [":Fonts"],
)

ios_application(
    name = "TypographyTestHost",
    testonly = True,
    bundle_id = "app.regram.tests.typography",
    families = ["iphone", "ipad"],
    minimum_os_version = "15.0",
    infoplists = ["Tests/Info.plist"],
    deps = [":TypographyTestHostLib"],
)

swift_library(
    name = "TypographyTestsLib",
    testonly = True,
    srcs = ["Tests/TypographyTests.swift"],
    deps = [":RGTypography", "//Regram/RGSimpleSettings", "//submodules/Display"],
)

ios_test_runner(
    name = "TypographyTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "TypographyTests",
    minimum_os_version = "15.0",
    runner = ":TypographyTestRunner",
    test_host = ":TypographyTestHost",
    deps = [":TypographyTestsLib"],
    visibility = ["//visibility:public"],
)
