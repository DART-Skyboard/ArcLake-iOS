
import SwiftUI

// Shared mol canvas state — accessible from both ViewModel and MolCanvasView
public final class MolCanvasState: ObservableObject {
    public static let shared = MolCanvasState()
    @Published public var pendingAtom: (symbol: String, atomicNumber: Int, color: UIColor)? = nil
}

// Extension to add mol canvas bridge to ArcLabViewModel
extension ArcLabViewModel {
    /// Called from OrbitDelta "To Canvas" button
    public func addToMolCanvas(element: ArcElement) {
        MolCanvasState.shared.pendingAtom = (
            symbol: element.elementSymbol,
            atomicNumber: element.protons,
            color: element.category.color
        )
    }
}
