# MARK: Regram — Regram source and dependency names.
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

rgdeps = [
    "//Regram/RGSimpleSettings:RGSimpleSettings"
]

swift_library(
    name = "LocalMediaResources",
    module_name = "LocalMediaResources",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = rgdeps + [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/ImageCompression:ImageCompression",
        "//submodules/PersistentStringHash:PersistentStringHash",
    ],
    visibility = [
        "//visibility:public",
    ],
)
