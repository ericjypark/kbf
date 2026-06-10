import Foundation

/// Pure math for smooth scrolling: splits a scroll distance into per-tick
/// deltas following an ease-out cubic, summing exactly to the total.
enum ScrollAnimation {
    static func deltas(total: Int32, steps: Int) -> [Int32] {
        guard steps > 0 else { return [total] }
        var out: [Int32] = []
        var emitted: Int32 = 0
        for i in 1...steps {
            let p = Double(i) / Double(steps)
            let eased = 1 - pow(1 - p, 3)
            let target = Int32((Double(total) * eased).rounded())
            out.append(target - emitted)
            emitted = target
        }
        return out
    }
}
