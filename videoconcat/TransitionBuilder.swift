//
//  TransitionBuilder.swift
//  videoconcat
//
//  Created by Laurent Denoue on 9/10/22.
//

import AVFoundation

struct TransitionComposition {

    let composition: AVComposition

    let videoComposition: AVVideoComposition
    
    let audioMix: AVMutableAudioMix

    func makePlayable() -> AVPlayerItem {
        let playerItem = AVPlayerItem(asset: composition.copy() as! AVAsset)
        playerItem.videoComposition = self.videoComposition
        return playerItem
    }

    func makeExportSession(preset: String, outputURL: URL) -> AVAssetExportSession? {
        let session = AVAssetExportSession(asset: composition, presetName: preset)
        session?.outputFileType = .mp4
        session?.outputURL = outputURL
        session?.audioMix = audioMix
        session?.timeRange = CMTimeRangeMake(start: CMTime.zero, duration: composition.duration)
        session?.videoComposition = videoComposition
        session?.canPerformMultiplePassesOverSourceMediaData = true
        return session
    }
}

struct TransitionCompositionBuilder {

    var assets = [AVAsset]()
    var timeRanges = [CMTimeRange]()
    private var transitionDuration: CMTime

    private var composition = AVMutableComposition()

    private var compositionVideoTracks = [AVMutableCompositionTrack]()

    static func clipTime(_ timeRange: CMTimeRange, assetDuration: CMTime) -> CMTimeRange {
        if timeRange.end > assetDuration {
            print("end > asset duration!")
            return CMTimeRange(start: CMTimeSubtract(assetDuration, timeRange.duration), duration: timeRange.duration)
        } else {
            return timeRange
        }
    }
    init?(clips: [Clip], transitionDuration: Float64 = 0.3) {

        guard !clips.isEmpty else { return nil }

        // initialize assets and ranges
        for clip in clips {
            // load the asset
            let asset = AVAsset(url: clip.assetURL)
            self.assets.append(asset)
            
            // clipping the given timeRange to fit within the asset's duration
            let timeRange = TransitionCompositionBuilder.clipTime(clip.timeRange, assetDuration: asset.duration)
            self.timeRanges.append(timeRange)
        }
        self.transitionDuration = CMTimeMakeWithSeconds(transitionDuration, preferredTimescale: 600)
    }

    mutating func buildComposition(_ renderSize: NSSize) -> TransitionComposition {

        var durations = timeRanges.map { $0.duration }

        durations.sort {
            CMTimeCompare($0, $1) < 1
        }

        // Make transitionDuration no greater than half the shortest video duration.
        let shortestVideoDuration = durations[0]
        var halfDuration = shortestVideoDuration
        halfDuration.timescale *= 2
        transitionDuration = CMTimeMinimum(transitionDuration, halfDuration)

        // 1 - build tracks
        buildCompositionTracks(composition: composition,
                               transitionDuration: transitionDuration,
                               assets: assets, assetsTimeRanges: timeRanges)

        // 2 - compute time ranges
        let timeRanges = calculateTimeRanges(transitionDuration: transitionDuration,
                                             assetsWithVideoTracks: assets, assetsTimeRanges: timeRanges)

        // 3 - build instructions
        let videoComposition = buildVideoCompositionAndInstructions(
            renderSize: renderSize,
            composition: composition,
            passThroughTimeRanges: timeRanges.passThroughTimeRanges,
            transitionTimeRanges: timeRanges.transitionTimeRanges)

        // 4 - OPTIONAL: build an AudioMix to ramp volume from 0 to 1 for transitionDuration
        /*let audioMix = AVMutableAudioMix()
        var params = [AVMutableAudioMixInputParameters]()
        let tracks = composition.tracks(withMediaType: .audio)
        var index = 0
        for time in timeRanges.transitionTimeRanges {
            let audioTrack = tracks[index % 2]
            let audioParam = AVMutableAudioMixInputParameters(track: audioTrack)
            let range = time.timeRangeValue
            audioParam.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: 1.0, timeRange: range)
            params.append(audioParam)
            index += 1
        }
        audioMix.inputParameters = params*/
        let audioMix = AVMutableAudioMix()
        return TransitionComposition(composition: composition, videoComposition: videoComposition, audioMix: audioMix)
    }

    // 1 - build tracks
    // because we're cross-fade, we use 2 video tracks to add fading instructions
    //
    private mutating func buildCompositionTracks(composition: AVMutableComposition,
                                            transitionDuration: CMTime,
                                            assets: [AVAsset], assetsTimeRanges: [CMTimeRange]) {

        let compositionVideoTrackA = composition.addMutableTrack(withMediaType: AVMediaType.video,
                                                                              preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid))!

        let compositionVideoTrackB = composition.addMutableTrack(withMediaType: AVMediaType.video,
                                                                              preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid))!

        let compositionAudioTrackA = composition.addMutableTrack(withMediaType: AVMediaType.audio,
                                                                              preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid))!

        let compositionAudioTrackB = composition.addMutableTrack(withMediaType: AVMediaType.audio,
                                                                              preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid))!

        compositionVideoTracks = [compositionVideoTrackA, compositionVideoTrackB]
        let compositionAudioTracks = [compositionAudioTrackA, compositionAudioTrackB]

        var cursorTime = CMTime.zero

        for i in 0..<assets.count {

            let trackIndex = i % 2

            let currentVideoTrack = compositionVideoTracks[trackIndex]
            let currentAudioTrack = compositionAudioTracks[trackIndex]

            let assetVideoTrack = assets[i].tracks(withMediaType: AVMediaType.video).first!
            let assetAudioTrack = assets[i].tracks(withMediaType: AVMediaType.audio).first

            currentVideoTrack.preferredTransform = assetVideoTrack.preferredTransform

            let timeRange = assetsTimeRanges[i]

            do {
                // video track: insert the slice of the clip's timeRange at cursorTime
                try currentVideoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: cursorTime)
                if let assetAudioTrack = assetAudioTrack {
                    // same for the audio track
                    try currentAudioTrack.insertTimeRange(timeRange, of: assetAudioTrack, at: cursorTime)
                }

            } catch let error as NSError {
                print("Failed to insert append track: \(error.localizedDescription)")
            }

            cursorTime = CMTimeAdd(cursorTime, timeRange.duration)
            cursorTime = CMTimeSubtract(cursorTime, transitionDuration)
        }
    }

    // 2 - compute time ranges
    private func calculateTimeRanges(transitionDuration: CMTime,
                                     assetsWithVideoTracks: [AVAsset], assetsTimeRanges: [CMTimeRange])
        -> (passThroughTimeRanges: [NSValue], transitionTimeRanges: [NSValue]) {

            var passThroughTimeRanges = [NSValue]()
            var transitionTimeRanges = [NSValue]()
            var cursorTime = CMTime.zero

            for i in 0..<assetsWithVideoTracks.count {

                var timeRange = CMTimeRangeMake(start: cursorTime, duration: assetsTimeRanges[i].duration)

                if i > 0 {
                    timeRange.start = CMTimeAdd(timeRange.start, transitionDuration)
                    timeRange.duration = CMTimeSubtract(timeRange.duration, transitionDuration)
                }

                if i + 1 < assetsWithVideoTracks.count {
                    timeRange.duration = CMTimeSubtract(timeRange.duration, transitionDuration)
                }

                passThroughTimeRanges.append(NSValue(timeRange: timeRange))
                cursorTime = CMTimeAdd(cursorTime, assetsTimeRanges[i].duration)
                cursorTime = CMTimeSubtract(cursorTime, transitionDuration)

                if i + 1 < assetsWithVideoTracks.count {
                    timeRange = CMTimeRangeMake(start: cursorTime, duration: transitionDuration)
                    transitionTimeRanges.append(NSValue(timeRange: timeRange))
                }
            }
            return (passThroughTimeRanges, transitionTimeRanges)
    }

    // 3 - build instructions
    private func buildVideoCompositionAndInstructions(renderSize: NSSize, composition: AVMutableComposition,
                                                          passThroughTimeRanges: [NSValue],
                                                          transitionTimeRanges: [NSValue])
        -> AVMutableVideoComposition {

            var instructions = [AVMutableVideoCompositionInstruction]()

            /// http://www.stackoverflow.com/a/31146867/1638273
            let videoTracks = compositionVideoTracks // guaranteed the correct time range
            let videoComposition = AVMutableVideoComposition(propertiesOf: composition)

            let transform = videoTracks[0].preferredTransform

            // create instructions from the various time ranges
            for i in 0..<passThroughTimeRanges.count {

                let trackIndex = i % 2
                let currentVideoTrack = videoTracks[trackIndex]

                let passThroughInstruction = AVMutableVideoCompositionInstruction()
                passThroughInstruction.timeRange = passThroughTimeRanges[i].timeRangeValue

                let passThroughLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: currentVideoTrack)

                passThroughLayerInstruction.setTransform(transform, at: CMTime.zero)

                passThroughInstruction.layerInstructions = [passThroughLayerInstruction]

                instructions.append(passThroughInstruction)

                if i < transitionTimeRanges.count {

                    let transitionInstruction = AVMutableVideoCompositionInstruction()
                    transitionInstruction.timeRange = transitionTimeRanges[i].timeRangeValue

                    let fromTrack = videoTracks[trackIndex]
                    let toTrack = videoTracks[1 - trackIndex]

                    let fromLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: fromTrack)
                    fromLayerInstruction.setTransform(transform, at: CMTime.zero)

                    // ramp opacity
                    fromLayerInstruction.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity:0.0, timeRange: transitionInstruction.timeRange)

                    let toLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: toTrack)
                    //toLayerInstruction.setTransform(transform, at: CMTime.zero)

                    transitionInstruction.layerInstructions = [fromLayerInstruction, toLayerInstruction]

                    instructions.append(transitionInstruction)

                }
            }

            videoComposition.instructions = instructions
            videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
            videoComposition.renderSize = renderSize

            return videoComposition
    }
}
