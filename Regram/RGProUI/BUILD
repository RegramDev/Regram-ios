load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")


swift_library(
    name = "RGProUI",
    module_name = "RGProUI",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Regram/RGKeychainBackupManager:RGKeychainBackupManager",
        "//Regram/RGItemListUI:RGItemListUI",
        "//Regram/RGLogging:RGLogging",
        "//Regram/RGSimpleSettings:RGSimpleSettings",
        "//Regram/RGStrings:RGStrings",
        "//Regram/RGAPI:RGAPI",
        "//Regram/RGAPIToken:RGAPIToken",
        "//Regram/RGSwiftUI:RGSwiftUI",
        #
        "//submodules/SettingsUI:SettingsUI",
        #
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/MtProtoKit:MtProtoKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/ItemListPeerItem:ItemListPeerItem",
        "//submodules/LocalizedPeerData:LocalizedPeerData",
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
