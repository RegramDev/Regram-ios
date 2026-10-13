load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("@rules_cc//cc:cc_test.bzl", "cc_test")

filegroup(
    name = "Licenses",
    srcs = ["Resources/RGUpdateSigner-zsign-LICENSE.txt", "//Regram/RGUpdateOpenSSL:Licenses"],
    visibility = ["//visibility:public"],
)

objc_library(
    name = "RGUpdateSigner",
    module_name = "RGUpdateSigner",
    enable_modules = True,
    srcs = glob(["Sources/*.mm", "Vendor/zsign/*.cpp", "Vendor/zsign/common/*.cpp", "Vendor/zsign/**/*.h"]),
    hdrs = ["Public/RGUpdateSigner.h"],
    includes = ["Public", "Vendor/zsign", "Vendor/zsign/common"],
    copts = ["-std=c++17", "-Wno-deprecated-declarations"],
    sdk_frameworks = ["Foundation", "Security"],
    deps = ["//Regram/RGUpdateOpenSSL:RGUpdateOpenSSL", "//third-party/ZipArchive:ZipArchive"],
    visibility = ["//visibility:public"],
)

objc_library(
    name = "CryptoCoexistenceChecks",
    srcs = ["Tests/CryptoCoexistenceChecks.mm"],
    copts = ["-std=c++17"],
    deps = [":RGUpdateSigner", "//submodules/OpenSSLEncryptionProvider:OpenSSLEncryptionProvider"],
    sdk_frameworks = ["Foundation"],
    testonly = True,
)

cc_test(
    name = "CryptoCoexistenceTests",
    srcs = ["Tests/CryptoCoexistenceMain.cpp"],
    deps = [":CryptoCoexistenceChecks"],
)
