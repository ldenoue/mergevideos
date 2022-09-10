//
//  ViewController.swift
//  videoconcat
//
//  Created by Laurent Denoue on 9/9/22.
//

import Cocoa
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
        let videoNames = ["screegle0","screegle1","screegle2"]
        let transitionDuration = 0.5 // half a second transition
        let renderSize = NSSize(width: 1920, height: 1080)
        var clips = [Clip]()
        for videoName in videoNames {
            if let videoPath = Bundle.main.path(forResource: videoName, ofType:"mp4") {
                let videoUrl = URL(fileURLWithPath: videoPath)
                let timeRange = CMTimeRange(start: .zero, duration: CMTimeMakeWithSeconds(2.0, preferredTimescale: 1))
                let clip = Clip(assetURL: videoUrl, timeRange: timeRange)
                clips.append(clip)
            }
        }
        
        var t = TransitionCompositionBuilder(clips: clips, transitionDuration: transitionDuration)
        if let comp = t?.buildComposition(renderSize) {
            
            // to show the composition live in the view
            /*let item = comp.makePlayable()
            let player = AVPlayer(playerItem: item)
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.frame = self.view.bounds
            self.view.wantsLayer = true
            self.view.layer?.addSublayer(playerLayer)
            player.play()*/
    
            if let tempURL = tempURLWithmp4Extension(), let session = comp.makeExportSession(preset: AVAssetExportPresetHighestQuality, outputURL: tempURL) {
                session.exportAsynchronously {
                    switch session.status{
                        case .completed:
                            print("exported to ",tempURL)
                            NSWorkspace.shared.open(tempURL)
                            break
                        case .failed:
                            print(session.error as Any)
                            break
                        default:
                            break
                        }
                    }
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

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }


}

