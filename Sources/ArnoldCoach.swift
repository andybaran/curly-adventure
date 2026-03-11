import Foundation

/// Speaks Arnold Schwarzenegger-style motivational quotes using either:
/// 1. **Audio clips** — Drop .mp3/.wav/.m4a files into ~/HeartRateRecorder/clips/
/// 2. **macOS TTS fallback** — Uses `say` command when no clips are available
///
/// Audio clip folder structure:
///   ~/HeartRateRecorder/clips/
///     warmup/       — Played when HR < 60% max
///     easy/         — Played when HR 60-70% max
///     moderate/     — Played when HR 70-80% max
///     hard/         — Played when HR 80-90% max
///     max/          — Played when HR > 90% max
///     start/        — Played when recording starts
///     stop/         — Played when recording stops
///     zone_change/  — Played on HR zone transitions
///
/// Put any number of audio files in each folder. One will be picked at random.
final class ArnoldCoach {

    /// HR zone thresholds (percentage of estimated max HR).
    /// Default max HR = 190. User can adjust.
    var maxHR: Int = 190

    private var lastQuoteTime: Date?
    private var lastZone: Zone?
    private var isSpeaking = false
    // `enabled` is declared below alongside voice settings

    /// Minimum seconds between quotes so Arnold doesn't talk over himself.
    var minInterval: TimeInterval = 45

    /// Base directory for audio clips.
    let clipsDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("HeartRateRecorder/clips")
    }()

    /// Cache of discovered audio files per subfolder.
    private var clipCache: [String: [URL]] = [:]
    private var clipsAvailable = false

    enum Zone: Int, CaseIterable {
        case warmup = 1   // < 60% max
        case easy = 2     // 60-70%
        case moderate = 3 // 70-80%
        case hard = 4     // 80-90%
        case max = 5      // 90%+

        var folderName: String {
            switch self {
            case .warmup:   return "warmup"
            case .easy:     return "easy"
            case .moderate: return "moderate"
            case .hard:     return "hard"
            case .max:      return "max"
            }
        }
    }

    // MARK: - TTS Quote Database (fallback when no clips)

    private let warmupQuotes = [
        "Come on, let's get that heart pumping! You are not here to rest!",
        "This is just the warm up. The real pain comes later!",
        "Wake up! Your grandma has a higher heart rate knitting!",
        "Let's go! The body achieves what the mind believes!",
        "You can rest when you're dead. Right now, we train!",
    ]

    private let easyQuotes = [
        "Good, you are warming up. But don't get comfortable!",
        "Strength does not come from winning. Your struggles develop your strength!",
        "The resistance that you fight physically in the gym makes you stronger!",
        "Nice and easy. But remember, no pain no gain!",
        "You're moving! That's more than the couch potatoes are doing!",
    ]

    private let moderateQuotes = [
        "Now we're talking! Push it! Push it harder!",
        "The mind always fails first, not the body. Keep going!",
        "You are one rep closer to your goal. Don't stop now!",
        "I told you, the last three or four reps is what makes the muscle grow!",
        "For me life is continuously being hungry. Never stop pushing!",
        "Good! You are not a baby! Keep that heart rate up!",
    ]

    private let hardQuotes = [
        "Yes! That's the zone! This is where champions are made!",
        "Your heart is a muscle. And right now, it is getting HUGE!",
        "Pain is temporary. Pride is forever! Keep pushing!",
        "I am not a self-made man. I got help. But right now, you do this alone!",
        "You can't climb the ladder of success with your hands in your pockets! Push!",
        "The worst thing I can be is the same as everybody else. Be extraordinary!",
        "Fantastic! You are a machine! An absolute machine!",
    ]

    private let maxQuotes = [
        "INCREDIBLE! You are an absolute BEAST! Maximum effort!",
        "This is it! The moment that separates the winners from the losers!",
        "You think this is hard? Try being Mr. Universe seven times! Keep going!",
        "I'll be back... but right now I'm HERE and so are YOU! Don't quit!",
        "Remember: What doesn't kill you makes you stronger! And bigger!",
        "You are operating at MAXIMUM CAPACITY! Arnold is PROUD of you!",
        "GET TO THE CHOPPER! Just kidding. Stay right here and PUSH!",
    ]

    private let zoneChangeQuotes: [Zone: [String]] = [
        .hard: [
            "Oh yeah! You just entered the HARD zone! Now the real workout begins!",
            "Heart rate climbing! This is where the magic happens!",
        ],
        .max: [
            "MAXIMUM POWER! You are in the RED ZONE! Absolutely phenomenal!",
            "You've gone FULL ARNOLD! This is the maximum zone!",
        ],
        .easy: [
            "Ah, coming back down. Good recovery. But don't stay here too long!",
        ],
        .warmup: [
            "Hey, what happened? Pick it up! Arnold does not accept quitting!",
        ],
    ]

    // MARK: - Initialization

    init() {
        scanForClips()
    }

    /// Scan the clips directory for audio files and cache results.
    func scanForClips() {
        clipCache.removeAll()
        let fm = FileManager.default
        let audioExtensions: Set<String> = ["mp3", "wav", "m4a", "aac", "aiff", "caf"]

        let subfolders = ["warmup", "easy", "moderate", "hard", "max", "start", "stop", "zone_change"]
        var totalClips = 0

        for folder in subfolders {
            let folderURL = clipsDir.appendingPathComponent(folder)
            guard let files = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
                continue
            }
            let audioFiles = files.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            if !audioFiles.isEmpty {
                clipCache[folder] = audioFiles
                totalClips += audioFiles.count
            }
        }

        clipsAvailable = totalClips > 0
    }

    /// Returns a status string describing clip availability.
    var clipStatus: String {
        if clipsAvailable {
            let total = clipCache.values.reduce(0) { $0 + $1.count }
            let folders = clipCache.keys.sorted().joined(separator: ", ")
            return "Audio clips: \(total) files in [\(folders)]"
        } else {
            return "No audio clips found. Using TTS. Add clips to: \(clipsDir.path)"
        }
    }

    // MARK: - Public Interface

    func setEnabled(_ on: Bool) {
        enabled = on
    }

    /// Call this with each new HR sample. Arnold will speak when appropriate.
    func processHeartRate(_ hr: Int) {
        guard enabled else { return }

        let zone = zoneFor(hr: hr)
        let now = Date()

        // Speak on zone change (with cooldown)
        if zone != lastZone {
            if shouldSpeak(now: now, minGap: 20) {
                if let clip = randomClip(from: "zone_change") {
                    playClip(clip)
                } else if let zoneQuotes = zoneChangeQuotes[zone] {
                    speak(zoneQuotes.randomElement()!)
                }
                lastQuoteTime = now
            }
        }

        // Periodic motivational quote
        if shouldSpeak(now: now, minGap: minInterval) {
            if let clip = randomClip(from: zone.folderName) {
                playClip(clip)
            } else {
                let quote = randomQuote(for: zone)
                speak(quote)
            }
            lastQuoteTime = now
        }

        lastZone = zone
    }

    /// Speak/play a one-time event (e.g., on recording start/stop).
    func speakEvent(_ text: String, clipFolder: String? = nil) {
        guard enabled else { return }
        if let folder = clipFolder, let clip = randomClip(from: folder) {
            playClip(clip)
        } else {
            speak(text)
        }
    }

    // MARK: - Audio Clip Playback

    /// Pick a random clip from the given subfolder, or nil if none available.
    private func randomClip(from folder: String) -> URL? {
        return clipCache[folder]?.randomElement()
    }

    /// Play an audio file using macOS `afplay` (built-in, supports mp3/wav/m4a/aac/aiff).
    private func playClip(_ url: URL) {
        isSpeaking = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            process.arguments = [url.path]
            try? process.run()
            process.waitUntilExit()
            self?.isSpeaking = false
        }
    }

    // MARK: - TTS Fallback

    private func zoneFor(hr: Int) -> Zone {
        let pct = Double(hr) / Double(maxHR) * 100
        switch pct {
        case ..<60:  return .warmup
        case ..<70:  return .easy
        case ..<80:  return .moderate
        case ..<90:  return .hard
        default:     return .max
        }
    }

    private func randomQuote(for zone: Zone) -> String {
        let quotes: [String]
        switch zone {
        case .warmup:  quotes = warmupQuotes
        case .easy:    quotes = easyQuotes
        case .moderate: quotes = moderateQuotes
        case .hard:    quotes = hardQuotes
        case .max:     quotes = maxQuotes
        }
        return quotes.randomElement()!
    }

    private func shouldSpeak(now: Date, minGap: TimeInterval) -> Bool {
        guard !isSpeaking else { return false }
        guard let last = lastQuoteTime else { return true }
        return now.timeIntervalSince(last) >= minGap
    }

    /// The macOS voice to use. "Alex" is a deep male voice; "Daniel" (British) or
    /// "Fred" are alternatives. Set via the `voice` property.
    var voice = "Alex"

    /// Speaking rate (words per minute). Lower = slower/more dramatic. Default 160.
    var speakingRate = 160

    private(set) var enabled = true

    /// Use macOS `say` command as TTS fallback when no audio clips are available.
    private func speak(_ text: String) {
        isSpeaking = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = ["-v", self.voice, "-r", "\(self.speakingRate)", text]
            try? process.run()
            process.waitUntilExit()
            self.isSpeaking = false
        }
    }
}
