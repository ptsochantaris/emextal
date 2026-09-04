import Foundation

/// Tracks how much of a model has arrived on disk, driving both a `Progress` and an optional line of
/// display text.
///
/// The byte count is measured from the cache directory rather than read from the Hub client's own
/// `Progress`. That progress object only learns about a file when the file *finishes*: while a shard
/// is downloading, its child progress contributes nothing, so the byte count, the completed
/// fraction and the reported throughput all sit frozen for as long as the shard takes — which for a
/// multi-gigabyte shard is many minutes. Measuring the blobs directory gives a figure that moves
/// while a shard is in flight, and stays correct across resumes because partly-downloaded shards
/// are already counted in it.
@MainActor
final class DownloadTracker {
    private let blobsDirectory: URL
    private let progress: Progress
    private let detailHandler: (@MainActor (String?) -> Void)?

    /// Total download size, taken from the Hub client's progress — the one figure on it that is
    /// reliable, being the sum of the file sizes in the repository listing.
    private var totalBytes: Int64 = 0

    /// Bytes already present, and the moment tracking began. The rate is the total gained since this
    /// point divided by the time since it — an average over the whole transfer.
    ///
    /// Measuring one burst against the next instead would report how fast a single flush writes to
    /// disk, tens of MB/s, rather than how fast the model is actually being acquired. Averaging
    /// across the whole transfer amortises the pauses between bursts, which is what makes the figure
    /// agree with the real transfer rate. The growing denominator also steadies it, so no separate
    /// smoothing is needed.
    private var sessionStart: (bytes: Int64, at: ContinuousClock.Instant)?

    private var lastCompleted: Int64 = 0

    private var rate: Double?

    /// Whether bytes were already present when tracking began, which decides between describing the
    /// opening phase as resuming or as starting.
    private var isResuming = false

    init(blobsDirectory: URL, progress: Progress, detailHandler: (@MainActor (String?) -> Void)?) {
        self.blobsDirectory = blobsDirectory
        self.progress = progress
        self.detailHandler = detailHandler
    }

    /// Records the expected total, learned from a progress callback, and takes the opening reading.
    ///
    /// Nothing can be displayed until the total is known, and no notification arrives for a
    /// directory that is merely sitting there, so this is the one read that has to be made directly
    /// rather than in response to a change.
    func setTotalBytes(_ total: Int64) async {
        guard total > 0, total != totalBytes else {
            return
        }
        totalBytes = total
        progress.totalUnitCount = total
        await poll()
    }

    /// Measures the bytes on disk, advances the progress and publishes the detail line. Driven by a
    /// timer rather than by the Hub client's callbacks, since those carry no byte count that moves
    /// while a shard is in flight.
    func poll() async {
        guard totalBytes > 0 else {
            return
        }

        let completed = min(await Self.bytesOnDisk(in: blobsDirectory), totalBytes)
        let now = ContinuousClock.now

        guard let start = sessionStart else {
            // The opening reading is a baseline only: bytes carried over from an earlier run did not
            // arrive just now, so they must not count towards the rate.
            sessionStart = (completed, now)
            lastCompleted = completed
            isResuming = completed > 0
            publish(completed: completed)
            return
        }

        // Nothing new on disk: leave the last reading in place rather than restating it. Restating
        // is what made the average appear to decay, since its denominator keeps growing between
        // bursts while its numerator does not.
        guard completed > lastCompleted else {
            return
        }

        lastCompleted = completed
        progress.completedUnitCount = completed

        let elapsed = (now - start.at).seconds
        let gained = completed - start.bytes
        if elapsed > 0, gained > 0 {
            rate = Double(gained) / elapsed
        }

        publish(completed: completed)
    }

    private func publish(completed: Int64) {
        guard let detailHandler else {
            return
        }

        var text = "\(completed.formatted(byteFormatter)) of \(totalBytes.formatted(byteFormatter))"
        if let rate, rate > 0 {
            text += " · \(Int64(rate).formatted(byteFormatter))/s"
        } else {
            text += isResuming ? " · Resuming…" : " · Starting…"
        }
        detailHandler(text)
    }

    /// Lands the progress on its end value, for when the download finishes between polls.
    func finish() {
        if progress.totalUnitCount <= 0 {
            progress.totalUnitCount = 1
        }
        progress.completedUnitCount = progress.totalUnitCount
    }

    /// Total size of everything in the blobs directory, including `.incomplete` shards still being
    /// written. Hops off the main actor: this is filesystem work on every tick.
    @concurrent
    private nonisolated static func bytesOnDisk(in directory: URL) async -> Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return contents.reduce(Int64(0)) { running, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return running + Int64(size)
        }
    }
}

private extension Duration {
    /// The duration as a fractional number of seconds, for rate arithmetic.
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
