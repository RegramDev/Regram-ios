load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

sgdeps = [
    "//Regram/RGGTranslate:RGGTranslate",
    "//Regram/RGSimpleSettings:RGSimpleSettings",
    "//Regram/RGTranslationLangFix:RGTranslationLangFix",
    "//Regram/RGWebSettingsScheme:RGWebSettingsScheme",
    "//Regram/RGGHSettingsScheme:RGGHSettingsScheme",
    "//Regram/RGConfig:RGConfig",
    "//Regram/RGLogging:RGLogging",
]

sgsrc = [
    "//Regram/RGIQTP:RGIQTP",
]

swift_library(
    name = "TelegramCore",
    module_name = "TelegramCore",
    srcs = sgsrc + glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = sgdeps + [
        "//submodules/TelegramApi:TelegramApi",
        "//submodules/MtProtoKit:MtProtoKit",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/CloudData:CloudData",
        "//submodules/CloudData/RGCloudKitGuard:RGCloudKitGuard",
        "//submodules/EncryptionProvider:EncryptionProvider",
        "//submodules/CryptoUtils:CryptoUtils",
        "//submodules/NetworkLogging:NetworkLogging",
        "//submodules/Reachability:Reachability",
        "//submodules/ManagedFile:ManagedFile",
        "//submodules/Utils/RangeSet:RangeSet",
        "//submodules/Utils/DarwinDirStat",
        "//submodules/Emoji",
        "//submodules/TelegramCore/FlatBuffers",
        "//submodules/TelegramCore/FlatSerialization",
        "//submodules/MurMurHash32"
    ],
    visibility = [
        "//visibility:public",
    ],
)
