import SwiftUI
import UIKit

extension UIApplication {
    static func dismissKeyboard() {
        shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    UIApplication.dismissKeyboard()
                }
            )
    }
}

extension View {
    func dismissKeyboardOnTap() -> some View {
        modifier(KeyboardDismissModifier())
    }
}
