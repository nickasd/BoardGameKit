import BoardGameKitHost
import SceneKit

/**
 A game board with hexagonal cells and support for undo operations.
 
 When instantiating this class, a `GameContext` must be active.
 */
public class HexBoardNode<Node: GameElementNode>: ButtonNode3D, BoardNode {
    
    public let cellRadius: Float
    public let cellHeight: Float
    public var cells = RecordedArray<BoardCellNode<HexTransform, Node>>()
    public var animationDuration = TimeInterval(1)

    public init(cellRadius: Float, cellHeight: Float) {
        self.cellRadius = cellRadius
        self.cellHeight = cellHeight
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public var cellWidth: Float {
        return cellRadius * sqrt(3)
    }
    
    public var cellLength: Float {
        return cellRadius * 2
    }
    
    public func position(forCellAt position: HexPosition) -> Vector3 {
        return Vector3(x: Float(position.x) * cellWidth / 2, y: Float(position.z) * cellHeight, z: -Float(position.y) * cellLength * 3 / 4)
    }
    
    public func rotation(for rotation: HexRotation) -> Float {
        return .pi * 2 * Float(rotation.rawValue) / Float(HexRotation.allCases.count)
    }
    
    public func transform(forBoundaryAt position: HexPosition, rotation: HexRotation) -> Transform {
        let rotation = self.rotation(for: rotation)
        let radius = cellWidth / 2
        return Transform(position: self.position(forCellAt: position) + Vector3(x: radius * cos(Float(rotation)), y: cellHeight, z: -radius * sin(Float(rotation))), rotation: Rotation(x: 0, y: .pi / 2 + rotation))
    }
    
    public func neighbourCells(around: HexPosition, withinDistance distance: Int) -> [CellNode] {
        return around.neighbourPositions(withinDistance: distance).compactMap({ position in cells.first(where: { $0.position == position }) })
    }

}
