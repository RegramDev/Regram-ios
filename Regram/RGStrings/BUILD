load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGStrings",
    module_name = "RGStrings",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AppBundle:AppBundle",
        "//Regram/RGLogging:RGLogging"
    ],
    visibility = [
        "//visibility:public",
    ],
)

filegroup(
    name = "RGLocalizableStrings",
    srcs = glob(["Strings/*.lproj/SGLocalizable.strings"]),
    visibility = [
        "//visibility:public",
    ],
)
