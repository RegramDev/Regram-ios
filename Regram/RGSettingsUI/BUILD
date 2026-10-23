load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

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
        "//Regram/RGLinkMetadata:RGLinkMetadata", # MARK: Regram
        "//submodules/AsyncDisplayKit",
        "//submodules/TelegramUI/Components/SliderComponent",
        "//Regram/RGItemListUI:RGItemListUI",
        "//Regram/RGLogging:RGLogging",
        "//Regram/RGSimpleSettings:RGSimpleSettings",
        "//Regram/RGTranscription:RGTranscription",
        "//Regram/RGAppUpdate:RGAppUpdate",
        "//Regram/RGGTranslate:RGGTranslate",
        "//Regram/RGStrings:RGStrings",
#        "//Regram/RGAPI:RGAPI",
        "//Regram/RGAPIToken:RGAPIToken",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/SearchBarNode", # MARK: Regram
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/MtProtoKit:MtProtoKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/LocalizedPeerData", # MARK: Regram
        "//submodules/OverlayStatusController:OverlayStatusController",
        "//submodules/AccountContext:AccountContext",
        "//submodules/AppBundle:AppBundle",
        "//submodules/TelegramUI/Components/Settings/PeerNameColorScreen",
        "//submodules/UndoUI:UndoUI",
        "//Regram/RGSwiftUI:RGSwiftUI",
        "//submodules/LegacyUI:LegacyUI",
        "//submodules/ComponentFlow",
        "//submodules/Components/ComponentDisplayAdapters",
        "//submodules/TelegramUI/Components/TabBarComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "RGSettingsLeadingButtonsTestsLib",
    testonly = True,
    srcs = [
        "Sources/RGSettingsLeadingButtonsNode.swift",
        "Tests/RGSettingsLeadingButtonsTests.swift",
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/ComponentFlow",
        "//submodules/TelegramUI/Components/NavigationBarComponent",
    ],
)

ios_test_runner(
    name = "RGSettingsLeadingButtonsTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "RGSettingsLeadingButtonsTests",
    minimum_os_version = "15.0",
    runner = ":RGSettingsLeadingButtonsTestRunner",
    deps = [":RGSettingsLeadingButtonsTestsLib"],
)
