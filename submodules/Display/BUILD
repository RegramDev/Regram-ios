# MARK: Regram — Regram source and dependency names.
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

rgsrc = [
    "//Regram/RGAppBadgeOffset:RGAppBadgeOffset"
]

rgdeps = [
    "//submodules/Utils/DeviceModel",
    "//Regram/RGSimpleSettings:RGSimpleSettings",
    "//Regram/RGTypography:RGTypography",
]

swift_library(
    name = "Display",
    module_name = "Display",
    srcs = rgsrc + glob([
        "Source/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = rgdeps + [
    	"//submodules/ObjCRuntimeUtils:ObjCRuntimeUtils",
    	"//submodules/UIKitRuntimeUtils:UIKitRuntimeUtils",
        "//submodules/AppBundle:AppBundle",
    	"//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Markdown:Markdown",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)
