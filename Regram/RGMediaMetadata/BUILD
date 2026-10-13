load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: Regram — "Media Info" in the photo/video viewer: resolution, codec, bitrate, frame rate,
# duration and size of a gallery item, read from the locally stored file only.
swift_library(
    name = "RGMediaMetadata",
    module_name = "RGMediaMetadata",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Regram/RGSimpleSettings:RGSimpleSettings",
        "//Regram/RGStrings:RGStrings",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
    ],
    visibility = [
        "//visibility:public",
    ],
)
