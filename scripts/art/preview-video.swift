// Turns the simulator recording into an App Store app preview (scripts/art/preview.sh runs it):
// trims it to the tour, speeds it up to fit `maxSeconds` if needed, scales and crops it to 886×1920 at 30 fps (H.264),
// and adds a silent stereo AAC track.
//   swift scripts/art/preview-video.swift <recording.mov> <recording start, s since 1970> <events.json> <out.mp4>
import AVFoundation
import Foundation

let maxSeconds = 29.5
let size = CGSize(width: 886, height: 1920)
let fps: Int32 = 30

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 5, let recordingStart = Double(args[2]) else {
    fail("usage: preview-video.swift <recording.mov> <recording start> <events.json> <out.mp4>")
}
let input = URL(filePath: args[1])
let output = URL(filePath: args[4])
guard let events = try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(filePath: args[3]))) as? [String: Double],
    let start = events["start"], let end = events["end"]
else { fail("events.json needs start and end") }

let asset = AVURLAsset(url: input)
guard let source = try await asset.loadTracks(withMediaType: .video).first else { fail("no video track") }
let assetDuration = try await asset.load(.duration)
let natural = try await source.load(.naturalSize)

// The tour, in recording time, kept inside the recording.
let from = max(0, start - recordingStart)
let to = min(assetDuration.seconds, end - recordingStart)
guard to > from else { fail("the tour (\(from)–\(to) s) isn't inside the \(assetDuration.seconds) s recording") }
let range = CMTimeRange(
    start: CMTime(seconds: from, preferredTimescale: 600), end: CMTime(seconds: to, preferredTimescale: 600))

let composition = AVMutableComposition()
guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
else { fail("can't add a video track") }
try video.insertTimeRange(range, of: source, at: .zero)
var length = range.duration
if length.seconds > maxSeconds {
    let target = CMTime(seconds: maxSeconds, preferredTimescale: 600)
    video.scaleTimeRange(CMTimeRange(start: .zero, duration: length), toDuration: target)
    length = target
}

// Silence: a stereo 48 kHz file as long as the video.
let silence = FileManager.default.temporaryDirectory.appending(path: "satchel-silence-\(UUID().uuidString).caf")
do {
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    let file = try AVAudioFile(forWriting: silence, settings: format.settings)
    let frames = AVAudioFrameCount(length.seconds * 48_000) + 4800
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    try file.write(from: buffer)
}
let silent = AVURLAsset(url: silence)
if let audioSource = try await silent.loadTracks(withMediaType: .audio).first,
    let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
{
    try audio.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: audioSource, at: .zero)
}

// Scale to fill 886×1920 (the capture is a hair taller), centered.
let scale = max(size.width / natural.width, size.height / natural.height)
let offset = CGPoint(x: (size.width - natural.width * scale) / 2, y: (size.height - natural.height * scale) / 2)
let instruction = AVMutableVideoCompositionInstruction()
instruction.timeRange = CMTimeRange(start: .zero, duration: length)
let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: video)
layer.setTransform(
    CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: offset.x, y: offset.y)),
    at: .zero)
instruction.layerInstructions = [layer]
let videoComposition = AVMutableVideoComposition()
videoComposition.renderSize = size
videoComposition.frameDuration = CMTime(value: 1, timescale: fps)
videoComposition.instructions = [instruction]

guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
    fail("can't export")
}
export.videoComposition = videoComposition
try? FileManager.default.removeItem(at: output)
try await export.export(to: output, as: .mp4)
try? FileManager.default.removeItem(at: silence)
print(String(format: "wrote %@ (%.1f s, %dx%d, %d fps)", output.path, length.seconds, Int(size.width), Int(size.height), fps))
