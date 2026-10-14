load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGStickerSave",
    module_name = "RGStickerSave",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//third-party/ZipArchive",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/DeviceAccess:DeviceAccess",
        "//submodules/Display:Display",
        "//submodules/AnimatedStickerNode:AnimatedStickerNode",
        "//submodules/LottieSettings:LottieSettings",
        "//submodules/WebPBinding:WebPBinding",
        "//submodules/SaveToCameraRoll:SaveToCameraRoll",
    ],
    visibility = ["//visibility:public"],
)
