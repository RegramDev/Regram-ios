load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGLocalGifts",
    module_name = "RGLocalGifts",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//Regram/RGSimpleSettings",
        "//Regram/RGStrings",
        "//Regram/RGSwiftUI",
        "//submodules/AccountContext",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/Display",
        "//submodules/PresentationDataUtils",
        "//submodules/PhoneNumberFormat",
    ],
    visibility = ["//visibility:public"],
)
