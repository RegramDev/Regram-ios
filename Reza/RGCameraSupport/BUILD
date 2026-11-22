load("@rules_cc//cc:objc_library.bzl", "objc_library")

objc_library(
    name = "RGCameraSupport",
    module_name = "RGCameraSupport",
    enable_modules = True,
    srcs = ["Sources/RGCameraSupport.m"],
    hdrs = ["Public/RGCameraSupport/RGCameraSupport.h"],
    includes = ["Public"],
    copts = ["-Werror"],
    sdk_frameworks = ["AVFoundation", "Foundation"],
    visibility = ["//visibility:public"],
)
