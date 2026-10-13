load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RGTranscription",
    module_name = "RGTranscription",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//Regram/RGSimpleSettings:RGSimpleSettings",
        "//Regram/RGStrings:RGStrings",
        "//submodules/AccountContext:AccountContext",
        "//submodules/AppBundle:AppBundle",
        "//submodules/Media/LocalAudioTranscription:LocalAudioTranscription",
        "//submodules/MediaPlayer:UniversalMediaPlayer",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
    ],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "TestAudio",
    srcs = ["Resources/RGSTTTest.m4a"],
    visibility = ["//visibility:public"],
)
