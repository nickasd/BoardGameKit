import BoardGameKitHost
import SceneKit

@MainActor public protocol BoardNode: ButtonNode3D {
    associatedtype ElementTransform: CellTransform
    associatedtype Node: GameElementNode
    typealias CellNode = BoardCellNode<ElementTransform, Node>
    typealias ElementPosition = ElementTransform.Position
    typealias ElementRotation = ElementTransform.Rotation

    var cells: RecordedArray<CellNode> { get set }
    func position(forCellAt position: ElementPosition) -> Vector3
    func rotation(for rotation: ElementRotation) -> Float
    var animationDuration: TimeInterval { get set }
}

public class BoardCellNode<Transform: CellTransform, Node: GameElementNode>: Equatable {
    
    public static func == (lhs: BoardCellNode, rhs: BoardCellNode) -> Bool {
        return lhs === rhs
    }
    
    public let transform: Transform
    public let node: Node
    
    public init(transform: Transform, node: Node) {
        self.transform = transform
        self.node = node
    }
    
}

extension BoardNode {
    
    public func cell(at position: ElementPosition) -> Node? {
        return cells.first(where: { $0.position == position })?.node
    }
    
    public func cells(at positions: [ElementPosition]) -> [Node] {
        return positions.map { position in
            guard let cell = cell(at: position) else {
                preconditionFailure("Cell at \(position) doesn't exist.")
            }
            return cell
        }
    }
    
    public func transform(for transform: ElementTransform) -> Transform {
        return Transform(position: self.position(forCellAt: transform.position), rotation: Rotation(x: 0, y: self.rotation(for: transform.rotation)))
    }
    
    public func addCell(_ cell: Node, at transform: ElementTransform, timeOffset: TimeInterval = 0) {
        addCells([cell], at: [transform], timeOffset: timeOffset)
    }
    
    public func addCells(_ cells: [Node], at transforms: [ElementTransform], timeOffset: TimeInterval = 0) {
        if cells.count != transforms.count {
            fatalError("precondition failure: cells.count == transforms.count")
        }
        let cells = zip(transforms, cells).map({ CellNode(transform: $0.0, node: $0.1) })
        self.cells.append(contentsOf: cells)
        let hasParent = cells.first?.node.parent != nil
        if cells.contains(where: { ($0.node.parent != nil) != hasParent }) {
            preconditionFailure("All nodes passed to BoardNode.addCells(_:at:timeOffset:) must have a parent, or all nodes must have none.")
        }
        if Logger.shared.level == .debug {
            for cell in cells {
                let node = TextNode3D(string: cell.transform.position.stringValue, fontSize: 5, alignment: .center, color: .blue)
                node.position.y = 0.01
                node.eulerAngles.x = -.pi / 2
                cell.node.addNode(node)
            }
        }
        if hasParent {
            for (i, cell) in cells.enumerated() {
                convertAndAddChildNode(cell.node)
                let transform = transform(for: cell.transform)
                addAnimation(MoveAnimation(node: cell.node, path: .alongControlPoint(transform.position + Vector3(x: 0, y: 0.1, z: 0)), endTransform: transform, duration: animationDuration, timeOffset: timeOffset + TimeInterval(i) / TimeInterval(cells.count)))
            }
        } else {
            for (i, cell) in cells.enumerated() {
                let node = cell.node
                node.opacity = 0
                let transform = transform(for: cell.transform)
                node.myTransform = transform + Vector3(x: 0, y: 0.05, z: 0)
                addNode(node)
                addAnimation(MoveAnimation(node: node, timingMode: .easeOut, endTransform: transform, duration: animationDuration * 0.5, timeOffset: timeOffset + max(0.01, 1.0 / TimeInterval(cells.count)) * TimeInterval(i), progress: { t in
                    node.opacity = min(1, 3 * t)
                }))
            }
        }
    }
    
    public func addNode(_ node: GameElementNode, at transform: ElementTransform, occupiedCells cells: [Node], at transforms: [ElementTransform]) {
        if cells.count != transforms.count {
            fatalError("precondition failure: cells.count == transforms.count")
        }
        let cells = zip(transforms, cells).map({ CellNode(transform: $0.0, node: $0.1) })
        self.cells.append(contentsOf: cells)
        convertAndAddChildNode(node)
        let transform = self.transform(for: transform)
        addAnimation(MoveAnimation(node: node, path: .alongControlPoint(transform.position + Vector3(x: 0, y: 0.1, z: 0)), endTransform: transform, duration: animationDuration))
    }
    
    public func removeCells(at positions: [ElementPosition]) {
        let indices = IndexSet(positions.map { position -> Int in
            guard let index = self.cells.firstIndex(where: { $0.position == position }) else {
                preconditionFailure("Element at \(position) doesn't exist.")
            }
            return index
        })
        let cells = cells.removeAndReturn(atOffsets: indices)
        for cell in cells {
            removeNode(cell.node)
        }
    }
    
    public func removeAllCells() {
        removeCells(at: cells.map({ $0.position }))
    }
    
}

extension BoardNode where ElementTransform: EuclidianCellTransform {
    
    public func highestCell(at position: ElementPosition) -> CellNode? {
        return cells.last(where: { $0.position.x == position.x && $0.position.y == position.y })
    }
    
    public func highestCellPosition(among positions: [ElementPosition]) -> Int? {
        return positions.compactMap({ highestCell(at: $0)?.position }).map({ $0.z }).max()
    }
    
    public func freeNeighbourPositions() -> [ElementPosition] {
        return cells.isEmpty ? [.zero] : Array(Set(cells.flatMap({ $0.position.neighbourPositions() })).filter({ cell(at: $0) == nil }))
    }
    
}

extension BoardCellNode {
    
    public var position: Transform.Position {
        return transform.position
    }
    
    public var rotation: Transform.Rotation {
        return transform.rotation
    }
    
}
