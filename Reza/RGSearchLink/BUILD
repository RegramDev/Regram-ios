load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: Regram — 聊天列表搜索框中的链接识别与「打开链接」入口行。
swift_library(
    name = "RGSearchLink",
    module_name = "RGSearchLink",
    srcs = glob(["Sources/**/*.swift"]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/AppBundle:AppBundle",
    ],
    visibility = ["//visibility:public"],
)
