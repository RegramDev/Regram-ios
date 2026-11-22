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
        "//Reza/RGAdFilter:RGAdFilter",
        "//Reza/RGAppGroupIdentifier",
        "//Reza/RGLocalGifts", # MARK: Regram
        "//Reza/RGItemListUI:RGItemListUI",
        "//Reza/RGLogging:RGLogging",
        "//Reza/RGSimpleSettings:RGSimpleSettings",
        "//Reza/RGSettingsUI:RGSettingsUI",
        "//Reza/RGGTranslate:RGGTranslate",
        "//Reza/RGStrings:RGStrings",
        "//Reza/RGAPI:RGAPI",
        "//Reza/RGAPIToken:RGAPIToken",
        "//Reza/RGSwiftUI:RGSwiftUI",
        "//Reza/RGTypography:RGTypography",
        "//submodules/LegacyUI:LegacyUI",
        "//submodules/LegacyMediaPickerUI:LegacyMediaPickerUI",
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
        "//submodules/TranslateUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)
