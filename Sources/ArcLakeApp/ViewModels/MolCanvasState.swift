
import SwiftUI

public final class MolCanvasState: ObservableObject {
    public static let shared = MolCanvasState()
    @Published public var pendingAtom: (symbol: String, z: Int, color: UIColor)? = nil
}
