load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGRegDate",
    module_name = "RGRegDate",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Regram/RGRegDateScheme:RGRegDateScheme",
        "//Regram/RGSimpleSettings:RGSimpleSettings",
        # RGAPI / RGAPIToken / RGDeviceToken were dropped with the web lookup: the date is now
        # derived on-device, so this module no longer needs a network or DeviceCheck path.
        "//Regram/RGStrings:RGStrings",

        "//submodules/AccountContext:AccountContext",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
    ],
    visibility = [
        "//visibility:public",
    ],
)