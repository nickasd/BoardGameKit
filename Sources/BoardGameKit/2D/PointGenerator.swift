import simd

public enum PointGenerator {
    public typealias Point = SIMD2<Float>
    
    case line(center: Point = Point(x: 0, y: 0), maxLength: Float, maxDistanceBetweenPoints: SIMD2<Float>)
    case arc(center: Point = Point(x: 0, y: 0), minRadius: Float, maxAngle: ClosedRange<Float> = (.pi * 1 / 5)...(.pi * 4 / 5), distanceBetweenPoints: Float)
    case circle(center: Point = Point(x: 0, y: 0), minRadius: Float, minDistanceBetweenPoints: Float)
    
    public func generate(count: Int) -> [(position: Point, angle: Float)] {
        switch self {
        case .line(let center, let maxLength, let maxDistanceBetweenPoints):
            if count == 1 {
                let position = center
                let rotation = Float(0)
                return [(position, rotation)]
            } else {
                let distanceBetweenPoints = min(maxLength / Float(count - 1), simd_length(maxDistanceBetweenPoints))
                let vectorBetweenPoints = maxDistanceBetweenPoints / simd_length(maxDistanceBetweenPoints) * distanceBetweenPoints
                let start = center - vectorBetweenPoints * Float(count - 1) / 2
                return (0..<count).map { i in
                    let position = start + vectorBetweenPoints * Float(i)
                    let rotation = -Float.pi
                    return (position, rotation)
                }
            }
        case .arc(let center, let minRadius, let maxAngle, let distanceBetweenPoints):
            let startAngle = maxAngle.lowerBound + (maxAngle.upperBound - maxAngle.lowerBound) / 2
            if count == 1 {
                let angle = startAngle
                let radius = minRadius
                let position = Point(x: center.x + radius * cos(angle), y: center.y - radius * sin(angle))
                let rotation = Float.pi
                return [(position, rotation)]
            } else {
                let angle = min(2 * asin(distanceBetweenPoints / 2 / minRadius), (maxAngle.upperBound - maxAngle.lowerBound) / Float(count - 1))
                let startAngle = startAngle + angle * Float(count - 1) / 2
                let radius = distanceBetweenPoints / 2 / sin(angle / 2)
                return (0..<count).map { i in
                    let angle = startAngle - Float(i) * angle
                    let position = Point(x: center.x + radius * cos(angle), y: center.y - radius * sin(angle))
                    let rotation = .pi / 2 + angle
                    return (position, rotation)
                }
            }
        case .circle(let center, let minRadius, let minDistanceBetweenPoints):
            if count == 1 {
                let position = center
                let rotation = Float.pi
                return [(position, rotation)]
            } else {
                let angle = 2 * Float.pi / Float(count)
                let radius = max(minRadius, minDistanceBetweenPoints / 2 / sin(angle / 2))
                let startAngle = -Float.pi / 2
                return (0..<count).map { i in
                    let angle = startAngle - Float(i) * angle
                    let position = Point(x: center.x + radius * cos(angle), y: center.y - radius * sin(angle))
                    let rotation = .pi / 2 + angle
                    return (position, rotation)
                }
            }
        }
    }
}
