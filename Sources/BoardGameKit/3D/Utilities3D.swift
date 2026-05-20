import BoardGameKitHost
import SceneKit

#if os(macOS)
public typealias Color = NSColor
public typealias Font = NSFont
#else
public typealias Color = UIColor
public typealias Font = UIFont
#endif
public typealias Vector3 = simd_float3
public typealias Vector2 = simd_float2
public typealias Rotation = simd_quatf

public struct Transform: Equatable {
    public var position: Vector3
    public var rotation: Rotation
    public var scale: Vector3
    
    public init(position: Vector3, rotation: Rotation = .identity, scale: Vector3 = .one) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
}

extension Rotation {
    
    public static var identity: Rotation {
        return Rotation(x: 0)
    }
    
    public init(lookingFrom from: Vector3, to: Vector3, up: Vector3 = SCNNode.simdLocalUp) {
        let front = simd_normalize(from - to)
        let cross = simd_cross(up, front)
        if cross == .zero { // if the rotation is invalid, SceneKit just doesn't render the object
            self.init(lookingAnyRollFrom: from, to: to)
        } else {
            let side = simd_normalize(cross)
            self.init(simd_float3x3(side, simd_cross(front, side), front))
        }
    }
    
    public init(lookingAnyRollFrom from: Vector3, to: Vector3, localFront: Vector3 = SCNNode.simdLocalFront) {
        self.init(from: localFront, to: simd_normalize(to - from))
    }
    
    public init(x: Float = 0, y: Float = 0, z: Float = 0) {
        let quaternion = Rotation(angle: z, axis: Vector3(x: 0, y: 0, z: 1)) * Rotation(angle: y, axis: Vector3(x: 0, y: 1, z: 0)) * Rotation(angle: x, axis: Vector3(x: 1, y: 0, z: 0))
        self.init(vector: quaternion.vector)
    }
    
}

extension Transform {
    
    public static func + (left: Transform, right: Vector3) -> Transform {
        var left = left
        left.position += right
        return left
    }
    
}

public func makeTranslationMatrix(tx: Float, ty: Float, tz: Float) -> simd_float4x4 {
    var matrix = matrix_identity_float4x4
    matrix[3, 0] = tx
    matrix[3, 1] = ty
    matrix[3, 2] = tz
    return matrix
}

#if os(iOS)
@MainActor
#endif
extension Sequence where Element: SCNNode {
    
    public var names: [String] {
        return map({ $0.name! })
    }
    
}

extension SCNAction {
    
    @MainActor public static func transform(_ transform: Transform, duration: TimeInterval) -> SCNAction {
        var oldTransform: Transform!
        return .customAction(duration: duration) { node, t in
            if oldTransform == nil {
                oldTransform = node.myTransform
            }
            let t = Float(min(1, t / duration))
            node.myTransform.position = simd_mix(oldTransform.position, transform.position, SIMD3(repeating: t))
            node.myTransform.rotation = simd_slerp(oldTransform.rotation, transform.rotation, t)
        }
//        return .group([
//            .move(to: SCNVector3(transform.position), duration: duration),
//            .rotate(toAxisAngle: transform.rotation.axis.x.isNaN ? SCNVector4(x: 1, y: 0, z: 0, w: 0) : SCNVector4(transform.rotation.axis.x, transform.rotation.axis.y, transform.rotation.axis.z, transform.rotation.angle), duration: duration)
////            .rotateTo(x: eulerAngles.x, y: eulerAngles.y, z: eulerAngles.z, duration: duration, usesShortestUnitArc: true) // SceneKit SCNNode.eulerAngles returns wrong rotation by 180° after setting SCNNode.simdOrientation (FB14979369) so we cannot set SCNNode.conversionNode.simdOrientation and then get SCNNode.conversionNode.eulerAngles
//        ])
    }
    
    public func withTimingMode(_ timingMode: SCNActionTimingMode) -> SCNAction {
        self.timingMode = timingMode
        return self
    }
    
}

@MainActor extension SCNNode {
    
    public func addChildNodeAndFadeIn(_ node: SCNNode) {
        node.opacity = 0
        node.runAction(.sequence([
            .wait(duration: 0.01), // SKNode.zPosition causes nodes to flicker by switching position for 1 frame (FB15945016)
            .fadeOpacity(to: 1, duration: 0.2)
        ]), forKey: "show")
        if node.parent == nil {
            addChildNode(node)
        }
    }
    
    public func fadeOutAndRemoveFromParent() {
        runAction(.sequence([
            .fadeOut(duration: 0.2),
            .removeFromParentNode()
        ]), forKey: "show")
    }
    
    public var myTransform: Transform {
        get {
            return Transform(position: simdPosition, rotation: simdOrientation, scale: simdScale)
        }
        set {
            simdPosition = newValue.position
            simdOrientation = newValue.rotation
            simdScale = newValue.scale
        }
    }
    
    public func convertTransform(_ transform: Transform, from: SCNNode?) -> Transform {
        return Transform(position: simdConvertPosition(transform.position, from: from), rotation: convertOrientation(transform.rotation, from: from), scale: transform.scale)
    }
    
    public func convertTransform(_ transform: Transform, to: SCNNode?) -> Transform {
        return Transform(position: simdConvertPosition(transform.position, to: to), rotation: convertOrientation(transform.rotation, to: to), scale: transform.scale)
    }
    
    func convertOrientation(_ orientation: Rotation, from: SCNNode?) -> Rotation {
        let conversionNode = SCNNode()
        conversionNode.setWorldTransform(from?.worldTransform ?? SCNMatrix4Identity)
        conversionNode.simdLocalRotate(by: orientation)
        conversionNode.transform = conversionNode.convertTransform(SCNMatrix4Identity, to: self)
        return conversionNode.simdOrientation
//        return (from?.simdWorldOrientation ?? .identity) * orientation / simdWorldOrientation
    }
    
    func convertOrientation(_ orientation: Rotation, to: SCNNode?) -> Rotation {
        let conversionNode = SCNNode()
        conversionNode.setWorldTransform(worldTransform)
        conversionNode.simdLocalRotate(by: orientation)
        conversionNode.transform = conversionNode.convertTransform(SCNMatrix4Identity, to: to)
        return conversionNode.simdOrientation
//        return simdWorldOrientation * orientation / (to?.simdWorldOrientation ?? .identity)
    }
    
    func firstAncestor<T>(_ block: (SCNNode) -> T?) -> T? {
        if let result = block(self) {
            return result
        }
        return parent?.firstAncestor(block)
    }
    
    public func position(forTextureCoordinate point: Vector2) -> Vector3 {
        let boundingBox = geometry?.boundingBox ?? boundingBox
        let boundingSize = Vector3(boundingBox.max) - Vector3(boundingBox.min)
        let point = point - Vector2(x: 0.5, y: 0.5)
        return Vector3(x: point.x * boundingSize.x, y: simdPosition.y + boundingSize.y + 0.001, z: -point.y * boundingSize.z)
    }
    
    public func textureCoordinate(for position: Vector3) -> Vector2 {
        let boundingBox = geometry?.boundingBox ?? boundingBox
        let boundingSize = Vector3(boundingBox.max) - Vector3(boundingBox.min)
        return Vector2(x: position.x / boundingSize.x, y: position.y / boundingSize.z) + Vector2(x: 0.5, y: 0.5)
    }
    
    /// Adds the given `node`. This method supports undo operations.
    public func addNode(_ node: SCNNode) {
        insertNode(node, at: childNodes.count)
    }
    
    /// Adds the given `node`. This method supports undo operations.
    public func insertNode(_ node: SCNNode, at index: Int) {
        Logger.shared.debug("Insert node \(node.description) at \(index) of \(description)")
        if node.parent == self ? index >= childNodes.count : index > childNodes.count {
            preconditionFailure("Index \(index) beyond bounds for \(childNodes.count) child nodes of \(description).")
        }
        insertChildNode(node, at: index)

        addUndoEvent(id: "Node._insertNode") { parent in
            if parent.childNodes.count <= index || parent.childNodes[index] != node {
                preconditionFailure("Removed node \(node.description) from \(parent.description) is not equal to expected node.")
            }
            parent._removeNode(at: index)
        }
    }
    
    /// Removes the given `node`. This method supports undo operations.
    public func removeNode(_ node: SCNNode) {
        guard let index = childNodes.firstIndex(of: node) else {
            preconditionFailure("Removed node is not a child.")
        }
        _removeNode(at: index)
    }

    private func _removeNode(at index: Int) {
        let node = childNodes[index]
        Logger.shared.debug("Remove node \(node.description) at \(index) of \(description)")
        node.removeFromParentNode()
        
        addUndoEvent(id: "Node._removeNode") { parent in
            parent.insertNode(node, at: index)
        }
    }
    
    /// Temporarily highlights the node in red to signal to the user that an action is invalid.
    public func runInvalidUseAnimation() {
        for material in geometry?.materials ?? [] {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.5
            material.emission.contents = Color.red
            SCNTransaction.completionBlock = {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.5
                material.emission.contents = Color.black
                SCNTransaction.commit()
            }
            SCNTransaction.commit()
        }
        for node in childNodes {
            node.runInvalidUseAnimation()
        }
    }
    
    /// Marks the node as highlighted (or not) with an animation.
    public func highlight(_ highlight: Bool) {
        for material in geometry?.materials ?? [] {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.3
            material.emission.contents = highlight ? Color(white: 0.5, alpha: 1) : Color.black
            SCNTransaction.commit()
        }
        for node in childNodes {
            node.highlight(highlight)
        }
    }
    
}

public class Plane: GameElementNode {
    
    public init(width: Float, height: Float, cornerRadius: Double = 0, material: SCNMaterial) {
        super.init()
        let plane = SCNPlane(width: CGFloat(width), height: CGFloat(height))
        plane.cornerRadius = cornerRadius
        plane.materials = [material]
        addChildNode(SCNNode(geometry: plane))
        childNodes[0].eulerAngles.x = -.pi / 2
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

extension SCNGeometry {
    
    public func copy(withMaterials materials: [SCNMaterial]) -> SCNGeometry {
        let copy = copy() as! SCNGeometry
        copy.materials = materials.map({ $0.copy() as! SCNMaterial })
        return copy
    }

}

/**
 A cylinder geometry.
 
 You can assign up to 3 materials which correspond to the side, top and bottom.
 */
public func Cylinder(radius: Float, height: Float) -> SCNGeometry {
//    let cylinder = SCNCylinder(radius: CGFloat(radius), height: CGFloat(height)) // SCNCylinder shows mirrored texture for base and top elements (FB11984386)
//    cylinder.radialSegmentCount = 20
//    return cylinder
    return RegularTile(radius: radius, edgeCount: 20, height: height)
}

/// A box geometry. You can assign up to 6 materials which correspond to the front, right, back, left, top and bottom.
public func Box(width: Float, height: Float, length: Float, chamferRadius: Float) -> SCNGeometry {
    return SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length), chamferRadius: CGFloat(chamferRadius))
}

/// A geometry created by extruding the regular shape with the given `radius` and `edgeCount` up by the given `height`. You can assign up to 3 materials which correspond to the bottom, top and side loop.
public func RegularTile(radius: Float, edgeCount: Int, height: Float) -> SCNGeometry {
//    let cylinder = SCNCylinder(radius: cellRadius, height: 0) // doesn't work as the texture coordinates do not work well with our images
//    cylinder.radialSegmentCount = 6
//    return cylinder
    var bottomVertices = [Vector3(x: 0, y: 0, z: 0)]
    for i in 0..<edgeCount {
        let angle = (.pi + 2 * .pi * Float(i)) / Float(edgeCount)
        let x = cos(angle) * radius
        let z = sin(angle) * radius
        bottomVertices.append(Vector3(x: x, y: 0, z: z))
    }
    var bottomTextureCoordinates = bottomVertices.map({ CGPoint(x: Double($0.x), y: Double(-$0.z)) })
    let textureCoordinatesMin = (x: bottomTextureCoordinates.map({ $0.x }).min()!, y: bottomTextureCoordinates.map({ $0.y }).min()!)
    let textureCoordinatesRange = (x: bottomTextureCoordinates.map({ $0.x }).max()! - textureCoordinatesMin.x, y: bottomTextureCoordinates.map({ $0.y }).max()! - textureCoordinatesMin.y)
    bottomTextureCoordinates = bottomTextureCoordinates.map({ CGPoint(x: 1 - ($0.x - textureCoordinatesMin.x) / textureCoordinatesRange.x, y: 1 - ($0.y - textureCoordinatesMin.y) / textureCoordinatesRange.y) })
    let topVertices = bottomVertices.reversed().map({ Vector3(x: $0.x, y: $0.y + height, z: $0.z) })
    let topAndBottomVertices = bottomVertices + topVertices
    let vertexSource = SCNGeometrySource(data: Data(bytes: topAndBottomVertices, count: MemoryLayout<Vector3>.size * topAndBottomVertices.count), semantic: .vertex, vectorCount: topAndBottomVertices.count, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<Vector3>.stride)
    let topTextureCoordinates = bottomTextureCoordinates.reversed().map({ CGPoint(x: 1 - $0.x, y: $0.y) })
    let textureCoordinatesSource = SCNGeometrySource(textureCoordinates: bottomTextureCoordinates + topTextureCoordinates)
    
    let bottomVertexIndices = (0..<edgeCount).flatMap { i -> [Int32] in
        let v3Top = Int32(max(1, (i + 2) % (edgeCount + 1)))
        return [0, Int32(i + 1), v3Top]
    }
    let bottomVertexElement = SCNGeometryElement(indices: bottomVertexIndices, primitiveType: .triangles)
    let topVertexIndices = bottomVertexIndices.map({ $0 + Int32(bottomVertices.count) })
    let topVertexElement = SCNGeometryElement(indices: topVertexIndices, primitiveType: .triangles)

    var sideVertexIndices = [Int32]()
    var sideTextureCoordinates = [Vector2]()
    for i in 0...edgeCount {
        let last = Int32(bottomVertices.count + topVertices.count - 2 - i % edgeCount)
        sideVertexIndices.append(contentsOf: [Int32(1 + i % edgeCount), last])
        sideTextureCoordinates.append(contentsOf: [Vector2(x: Float(i) / Float(edgeCount), y: 0), Vector2(x: Float(i) / Float(edgeCount), y: 1)])
    }
    let sideVertexElement = SCNGeometryElement(data: Data(bytes: sideVertexIndices, count: MemoryLayout<Int32>.size * sideVertexIndices.count), primitiveType: .triangleStrip, primitiveCount: 2 * edgeCount, bytesPerIndex: MemoryLayout<Int32>.size)
    let sideTextureCoordinatesSource = SCNGeometrySource(data: Data(bytes: sideTextureCoordinates, count: MemoryLayout<Vector2>.size * sideTextureCoordinates.count), semantic: .texcoord, vectorCount: sideTextureCoordinates.count, usesFloatComponents: true, componentsPerVector: 2, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<Vector2>.stride)
    
    return SCNGeometry(sources: [vertexSource, textureCoordinatesSource, sideTextureCoordinatesSource], elements: [bottomVertexElement, topVertexElement, sideVertexElement])
}

extension SCNMaterial {
    
    public static var black: SCNMaterial {
        return SCNMaterial(diffuseContents: Color.black)
    }
    
    public convenience init(diffuseContents: Any) {
        self.init()
        diffuse.contents = diffuseContents
    }
    
}
