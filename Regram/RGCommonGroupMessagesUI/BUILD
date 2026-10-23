load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGCommonGroupMessagesUI",
    module_name = "RGCommonGroupMessagesUI",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//Regram/RGSimpleSettings:RGSimpleSettings",
        "//Regram/RGStrings:RGStrings",
        "//submodules/AccountContext",
        "//submodules/AsyncDisplayKit",
        "//submodules/AvatarNode",
        "//submodules/Display",
        "//submodules/LocalizedPeerData",
        "//submodules/Postbox",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
    ],
    visibility = ["//visibility:public"],
)
