import AVFoundation
import WatchKit
import SpottersaurusKit

@MainActor
final class WatchLiveSetFeedback {
    private let logger: any AppLogger
    private let speechSynthesizer = AVSpeechSynthesizer()

    init(logger: any AppLogger = LoggerGroup.watch) {
        self.logger = logger
    }

    func playGrindingCue() {
        logger.info(.liveSet, "playing grinding haptic")
        WKInterfaceDevice.current().play(.directionUp)
    }

    func playRackItCue() {
        logger.notice(.liveSet, "playing rack-it haptic and audio cue")
        WKInterfaceDevice.current().play(.failure)
        let utterance = AVSpeechUtterance(string: "Rack it")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1
        speechSynthesizer.speak(utterance)
    }

    func playRestCompleteCue() {
        logger.info(.liveSet, "playing rest completion haptic")
        WKInterfaceDevice.current().play(.success)
    }
}
