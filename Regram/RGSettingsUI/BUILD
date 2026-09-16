load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

filegroup(
    name = "RGUIAssets",
    srcs = glob(["Images.xcassets/**"]),
    visibility = ["//visibility:public"],
)

swift_library(
    name = "RGSettingsUI",
    module_name = "RGSettingsUI",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Regram/RGItemListUI:RGItemListUI",
        "//Regram/RGLogging:RGLogging",
        "//Regram/RGSimpleSettings:RGSimpleSettings",
        "//Regram/RGStrings:RGStrings",
#        "//Regram/RGAPI:RGAPI",
        "//Regram/RGAPIToken:RGAPIToken",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/MtProtoKit:MtProtoKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/OverlayStatusController:OverlayStatusController",
        "//submodules/AccountContext:AccountContext",
        "//submodules/AppBundle:AppBundle",
        "//submodules/TelegramUI/Components/Settings/PeerNameColorScreen",
        "//submodules/UndoUI:UndoUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)
