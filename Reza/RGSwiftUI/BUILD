load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGSwiftUI",
    module_name = "RGSwiftUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        # "-warnings-as-errors",
    ],
    deps = [
        "//submodules/LegacyUI:LegacyUI",
        "//submodules/Display:Display",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//Reza/RGSimpleSettings:RGSimpleSettings",
        "//Reza/RGTypography:RGTypography",
        "//Reza/RGStrings:RGStrings",
    ],
    visibility = [
        "//visibility:public",
    ],
)
