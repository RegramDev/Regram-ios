#!/usr/bin/env python3
"""Run the production converter and Objective-C bindings against real local audio, without an account.

Requires a macOS SDK, ffmpeg, and pkg-config for libavformat/libavcodec/libavutil/libswresample/opus.
The host codec libraries are not the libraries bundled in the iOS application.
"""
from pathlib import Path
import json
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]

def run(args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, **kwargs)

with tempfile.TemporaryDirectory(prefix='regram-voice-') as temp:
    out = Path(temp)
    flags = shlex.split(subprocess.check_output(['pkg-config', '--cflags', '--libs', 'libavformat', 'libavcodec', 'libavutil', 'libswresample', 'opus'], text=True))
    includes = [f for f in flags if f.startswith('-I')]
    includes += ['-I'+str(Path(f[2:]).parent) for f in includes if Path(f[2:]).name == 'opus']
    links = [f for f in flags if not f.startswith('-I')]
    modules = []
    for name, headers in {
        'FFMpegBinding': ROOT / 'submodules/FFMpegBinding/Public/FFMpegBinding',
        'OpusBinding': ROOT / 'submodules/OpusBinding/PublicHeaders/OpusBinding',
    }.items():
        module = out / name
        module.mkdir()
        selected = list(headers.glob('*.h'))
        if name == 'OpusBinding':
            selected = [headers/'TGDataItem.h', headers/'TGOggOpusWriter.h']
        (module/'module.modulemap').write_text('module '+name+' {\n'+''.join(' header "'+str(h)+'"\n' for h in selected)+' export *\n}\n')
        modules.append(module)
    ff = ROOT/'submodules/FFMpegBinding'
    opus = ROOT/'submodules/OpusBinding'
    sources = [ff/'Sources'/f'{name}.m' for name in ['FFMpegAVFormatContext', 'FFMpegAVCodec', 'FFMpegAVCodecContext', 'FFMpegAVFrame', 'FFMpegPacket', 'FFMpegSWResample', 'FFMpegAVIOContext']]
    sources += [opus/'Sources/TGDataItem.m', opus/'Sources/opusenc/opusenc.m', opus/'Sources/opusenc/opus_header.c']
    sources += list((opus/'Sources/ogg').glob('*.c')) + list((opus/'Sources/opusfile').glob('*.c'))
    objects = []
    for i, source in enumerate(sources):
        obj = out/f'binding-{i}.o'
        command = ['xcrun', 'clang', '-c', '-O1', '-Wno-deprecated-declarations', source, '-o', obj]
        if source.suffix == '.m': command += ['-fobjc-arc', '-fmodules']
        command += includes + ['-I'+str(ff/'Public'), '-I'+str(opus/'PublicHeaders/OpusBinding'), '-I'+str(opus/'Sources'), '-I'+str(opus/'Sources/opusfile')]
        run(command)
        objects.append(obj)
    main = out/'main.swift'
    main.write_text(r'''
import Foundation
import OpusBinding

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
for name in CommandLine.arguments.dropFirst(2) {
    let url = directory.appendingPathComponent(name)
    let voice = try rgConvertVoiceFile(url)
    precondition(voice.data.starts(with: Data("OggS".utf8)), "Ogg container")
    precondition(voice.duration > 0 && voice.waveformSamples.count == 200, "duration and waveform")
    let state = try JSONSerialization.jsonObject(with: voice.resumeData) as! [String: Any]
    precondition(!state.isEmpty, "persisted recorder metadata")
    let dataItem = TGDataItem(data: voice.data)!
    let writer = TGOggOpusWriter()
    // This is the production recorder's fallback when reopening a finished draft.
    precondition(writer.beginAppend(with: dataItem), "native recorder can reopen imported voice")
    precondition(writer.writeFrame(nil, frameByteCount: 0), "reopened stream can be finished")
    try voice.data.write(to: directory.appendingPathComponent(name+".ogg"))
    print("converted", name, voice.duration)
}
let invalid = directory.appendingPathComponent("invalid.mp3")
do { _ = try rgConvertVoiceFile(invalid); fatalError("invalid input accepted") } catch RGVoiceImportError.invalidAudio {}
do { _ = try rgConvertVoiceFile(directory.appendingPathComponent("missing.wav")); fatalError("missing input accepted") } catch RGVoiceImportError.invalidAudio {}
do { _ = try rgConvertVoiceFile(URL(string: "https://example.invalid/audio.mp3")!); fatalError("remote input accepted") } catch RGVoiceImportError.invalidAudio {}
do { _ = try rgConvertVoiceFile(invalid, isCancelled: { true }); fatalError("cancelled input accepted") } catch RGVoiceImportError.cancelled {}
var polls = 0
do {
    _ = try rgConvertVoiceFile(directory.appendingPathComponent("long.flac"), isCancelled: { polls += 1; return polls > 8 })
    fatalError("in-flight cancellation ignored")
} catch RGVoiceImportError.cancelled {}
precondition(rgIsVoiceImportFile(directory.appendingPathComponent("VOICE.MP3")), "uppercase extension")
precondition(!rgIsVoiceImportFile(directory.appendingPathComponent("image.png")), "other files stay on file path")
print("invalid, missing, remote, cancellation and file dispatch checks passed")
''')
    binary = out/'checks'
    run(['xcrun', 'swiftc', '-warnings-as-errors', ROOT/'Regram/RGVoiceMessages/Sources/RGVoiceFileConverter.swift', main, *objects, *sum((['-I', p] for p in modules), []), '-I', ff/'Public', *links, '-framework', 'Foundation', '-framework', 'CoreMedia', '-framework', 'VideoToolbox', '-o', binary])
    cases = [('mp3', 'libmp3lame'), ('m4a', 'aac'), ('aac', 'aac'), ('wav', 'pcm_s16le'), ('ogg', 'vorbis'), ('opus', 'libopus'), ('flac', 'flac'), ('aiff', 'pcm_s16be')]
    names = []
    for i, (extension, codec) in enumerate(cases):
        name = f'sample.{extension}'
        names.append(name)
        run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=2.35', '-ar', '44100' if i%2 and extension!='opus' else '48000', '-ac', '2' if i%2 or extension=='ogg' else '1', '-c:a', codec, '-strict', '-2', out/name])
    for name, duration in [('short.wav', '0.03'), ('long.flac', '30')]:
        run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', f'sine=duration={duration}', out/name])
    names.append('short.wav')
    (out/'invalid.mp3').write_text('not an audio file')
    run([binary, out, *names])
    for name in names:
        probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-of', 'json', out/(name+'.ogg')], text=True))['streams'][0]
        assert probe['codec_name'] == 'opus' and probe['channels'] == 1 and probe['sample_rate'] == '48000', name
        expected = 0.03 if name == 'short.wav' else 2.35
        assert abs(float(probe['duration'])-expected) < 0.12, (name, probe['duration'])
        run(['ffmpeg', '-v', 'error', '-i', out/(name+'.ogg'), '-f', 'null', '-'])
    print(f'Voice import: {len(names)} real codec round-trips plus invalid-input, draft-resume and cancellation checks passed')
