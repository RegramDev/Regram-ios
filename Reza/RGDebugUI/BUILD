load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

config_setting(
    name = "debug_build",
    values = {
        "compilation_mode": "dbg",
    },
)

config_setting(
    name = "fastbuild_build",
    values = {
        "compilation_mode": "fastbuild",
    },
)

flex_dependency = select({
    ":debug_build": [
        "@flex_sdk//:FLEX"
    ],
    ":fastbuild_build": [
        "@flex_sdk//:FLEX"
    ],
    "//conditions:default": [],
})


swift_library(
    name = "RGDebugUI",
    module_name = "RGDebugUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Reza/RGAppGroupIdentifier:RGAppGroupIdentifier",
        "//Reza/RGItemListUI:RGItemListUI",
        "//Reza/RGLogging:RGLogging",
        "//Reza/RGSimpleSettings:RGSimpleSettings",
        "//Reza/RGStrings:RGStrings",
        "//Reza/RGSwiftUI:RGSwiftUI",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/LegacyUI:LegacyUI",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/Display:Display",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/OverlayStatusController:OverlayStatusController",
        "//submodules/AccountContext:AccountContext",
        "//submodules/UndoUI:UndoUI"
    ] + flex_dependency,
    visibility = [
        "//visibility:public",
    ],
)
