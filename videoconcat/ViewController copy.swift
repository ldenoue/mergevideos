//
//  ViewController.swift
//  videoconcat
//
//  Created by Laurent Denoue on 9/9/22.
//

import Cocoa
//import CoreVideo
//import CoreMedia
import AVFoundation

struct Clip {
    var assetURL: URL
    var timeRange: CMTimeRange
}
class ViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidAppear() {
        //let videoNames = ["room","screegle","citizen"]
        let videoNames = ["screegle0","screegle1","screegle2"]
        var clips = [Clip]()
        for videoName in videoNames {
            if let videoPath = Bundle.main.path(forResource: videoName, ofType:"mp4") {
                let videoUrl = URL(fileURLWithPath: videoPath)
                print(videoUrl)
                let timeRange = CMTimeRange(start: .zero, duration: CMTimeMakeWithSeconds(2.0, preferredTimescale: 1))
                let clip = Clip(assetURL: videoUrl, timeRange: timeRange)
                clips.append(clip)
            }
        }
        
        concat(clips) { url, err in
            if let url = url {
                print("success=",url)
                NSWorkspace.shared.open(url)
            } else {
                print("error=",err)
            }
        }
    }

    func tempURLWithmp4Extension() -> URL?{
        let directory = NSTemporaryDirectory() as NSString
        if directory != "" {
            let path = directory.appendingPathComponent(UUID.init().uuidString.appending(".mp4"))
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    //private let TRANSITION_DURATION = CMTimeMake(value: 3, timescale: 1)
    let TRANSITION_DURATION = CMTimeMakeWithSeconds(0.3, preferredTimescale: 600)
    private func calculateTimeRanges(assets: [AVAsset])
            -> (passThroughTimeRanges: [NSValue], transitionTimeRanges: [NSValue]) {
                
                var passThroughTimeRanges:[NSValue] = [NSValue]()
                var transitionTimeRanges:[NSValue] = [NSValue]()
                var cursorTime = CMTime.zero
                
                for i in 0...(assets.count - 1) {
                    let asset = assets[i]
                    if TRANSITION_DURATION <= asset.duration {
                        var timeRange = CMTimeRangeMake(start: cursorTime, duration: asset.duration)
                        
                        if i > 0 {
                            timeRange.start = CMTimeAdd(timeRange.start, TRANSITION_DURATION)
                            timeRange.duration = CMTimeSubtract(timeRange.duration, TRANSITION_DURATION)
                        }
                        
                        if i + 1 < assets.count {
                            timeRange.duration = CMTimeSubtract(timeRange.duration, TRANSITION_DURATION)
                        }
                        
                        passThroughTimeRanges.append(NSValue.init(timeRange: timeRange))
                        
                        cursorTime = CMTimeAdd(cursorTime, asset.duration)
                        cursorTime = CMTimeSubtract(cursorTime, TRANSITION_DURATION)
                        
                        if i + 1 < assets.count {
                            timeRange = CMTimeRangeMake(start: cursorTime, duration: TRANSITION_DURATION)
                            transitionTimeRanges.append(NSValue.init(timeRange: timeRange))
                        }
                    }
                }
                return (passThroughTimeRanges, transitionTimeRanges)
        }
    
    
    func concat(_ clips: [Clip], completion: @escaping (URL?,String?) -> Void) -> Void {
        
        var assets = [AVAsset]()
        for clip in clips {
            assets.append(AVAsset(url: clip.assetURL))
        }
        var t = TransitionCompositionBuilder(assets: assets, transitionDuration: 1.0)
        if let comp = t?.buildComposition() {
            let item = comp.makePlayable()
            let player = AVPlayer(playerItem: item)
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.frame = self.view.bounds
            self.view.wantsLayer = true
            self.view.layer?.addSublayer(playerLayer)
            player.play()
            
        }
    }
    
    // inspired by https://gist.github.com/Tulakshana/01fe0c15b71180c2adf78d64fbaa44b5
    func concat2(_ clips: [Clip], completion: @escaping (URL?,String?) -> Void) -> Void {
        
        var assets = [AVAsset]()
        for clip in clips {
            assets.append(AVAsset(url: clip.assetURL))
        }
        let (pass,transition) = calculateTimeRanges(assets: assets)
        print(pass,transition)
        let composition = AVMutableComposition()
        guard let videoTrack1 = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return completion(nil,"error video track") }
        guard let videoTrack2 = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return completion(nil,"error video track2") }
        guard let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return completion(nil,"error audio track") }
        var currentTime = CMTime.zero
        var instructions = [AVMutableVideoCompositionInstruction]()
        var params = [AVMutableAudioMixInputParameters]()

        let FADE = true
        var index = 0
        for clip in clips {
            print(index)
            let videoTrack = (index % 2 == 0) ? videoTrack1 : videoTrack2
            let otherVideoTrack = (index % 2 == 0) ? videoTrack2 : videoTrack1
            //let videoTrack = videoTrack1
            let asset = AVAsset(url: clip.assetURL)
            let timeRange = clip.timeRange
            if timeRange.start < .zero || timeRange.duration > asset.duration {
                return completion(nil,"invalid time range")
            }
            if let assetVideoTrack = asset.tracks(withMediaType: .video).first {
                //videoTrack.preferredTransform = assetVideoTrack.preferredTransform
                //let timeRange = pass[index].timeRangeValue
                let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
                try? videoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: currentTime)
                let instruction = AVMutableVideoCompositionInstruction()
                //instruction.timeRange = CMTimeRangeMake(start: currentTime, duration: timeRange.duration)
                instruction.timeRange = pass[index].timeRangeValue
                let videoLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
                videoLayerInstruction.setTransform(videoTrack.preferredTransform, at: currentTime)
                instruction.layerInstructions = [videoLayerInstruction]
                instructions.append(instruction)
                if FADE, index < transition.count {
                    print("adding fade")
                    let instruction = AVMutableVideoCompositionInstruction()
                    instruction.timeRange = transition[index].timeRangeValue
                    let fLInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
                    fLInstruction.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity:0.0, timeRange: instruction.timeRange)
                    let tLInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: otherVideoTrack)
                    instruction.layerInstructions = [fLInstruction, tLInstruction]
                    instructions.append(instruction)
                }
                if let assetAudioTrack = asset.tracks(withMediaType: .audio).first {
                    try? audioTrack.insertTimeRange(timeRange, of: assetAudioTrack, at: currentTime)
                    let audioParam = AVMutableAudioMixInputParameters(track: audioTrack)
                    let range = CMTimeRange(start: currentTime, duration: CMTimeMakeWithSeconds(1, preferredTimescale: 1))
                    audioParam.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: 1.0, timeRange: range)
                    //audioParam.setVolume(0.2, at: currentTime)
                    params.append(audioParam)
                } else { print("err audio")}

                currentTime = CMTimeAdd(currentTime, timeRange.duration)
                currentTime = CMTimeSubtract(currentTime, TRANSITION_DURATION)
                //currentTime = CMTimeAdd(currentTime, asset.duration)
            } else { print("err video")}
            index += 1
        }


        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            return completion(nil,"export session error")
        }
        
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = params
        export.audioMix = audioMix

        let tempUrl = tempURLWithmp4Extension()
        export.outputURL = tempUrl

        export.outputFileType = AVFileType.mp4

        let mutableVideoComposition = AVMutableVideoComposition(propertiesOf: composition)
        mutableVideoComposition.instructions = instructions
        mutableVideoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        mutableVideoComposition.renderSize =  CGSize(width: 1920, height: 1080)
        //export.timeRange = CMTimeRangeMake(start: .zero, duration: composition.duration)
        export.videoComposition = mutableVideoComposition
    
        export.exportAsynchronously {
        switch export.status{
            case .completed:
                //handle successful composition that is at
                //tempURL location
                completion(tempUrl,nil)
                break
            case .failed:
                //print(export.error as Any)
                completion(nil,export.error?.localizedDescription)
                break
            default:
                break
            }
        }
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }


}

