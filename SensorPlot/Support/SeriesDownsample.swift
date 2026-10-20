import Foundation

enum SeriesDownsample {
    /// Evenly pick up to `maxPoints` samples from a time-ordered series (keeps first/last).
    static func stride(_ samples: [SamplePoint], maxPoints: Int) -> [SamplePoint] {
        guard samples.count > maxPoints, maxPoints > 2 else { return samples }
        let step = Double(samples.count - 1) / Double(maxPoints - 1)
        var result: [SamplePoint] = []
        result.reserveCapacity(maxPoints)
        for i in 0..<maxPoints {
            let index = min(samples.count - 1, Int((Double(i) * step).rounded()))
            result.append(samples[index])
        }
        return result
    }
}
