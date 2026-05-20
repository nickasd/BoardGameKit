import BoardGameKitHost
import SceneKit

/**
 A game board with square cells and support for undo operations.
 
 When instantiating this class, a `GameContext` must be active.
 */
public class SquareBoardNode<Node: GameElementNode>: ButtonNode3D, BoardNode {
    
    public let cellSize: Float
    public let cellHeight: Float
    public var cells = RecordedArray<BoardCellNode<SquareTransform, Node>>()
    public var animationDuration = TimeInterval(1)

    public init(cellSize: Float, cellHeight: Float) {
        self.cellSize = cellSize
        self.cellHeight = cellHeight
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func position(forCellAt position: SquarePosition) -> Vector3 {
        return Vector3(x: Float(position.x) * cellSize, y: Float(position.z) * cellHeight, z: Float(position.y) * cellSize)
    }
    
    public func rotation(for rotation: SquareRotation) -> Float {
        return .pi * 2 * Float(rotation.rawValue) / Float(SquareRotation.allCases.count)
    }

}
