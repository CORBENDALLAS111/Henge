import SwiftUI
import UIKit

struct KeyboardFrameReader: UIViewRepresentable {
    var changed: (CGRect) -> Void
    func makeUIView(context: Context) -> Reader { Reader() }
    func updateUIView(_ view: Reader, context: Context) { view.changed = changed }
    final class Reader: UIView {
        var changed: (CGRect) -> Void = { _ in }
        private var observers: [NSObjectProtocol] = []
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardWillHideNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    guard let self, let window = self.window else { return }
                    var rect = CGRect.zero
                    if name != UIResponder.keyboardWillHideNotification,
                       let value = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                        let inWindow = window.convert(value.cgRectValue, from: window.screen.coordinateSpace)
                        let overlap = self.bounds.intersection(self.convert(inWindow, from: window))
                        if !overlap.isNull && overlap.height > 0 { rect = overlap }
                    }
                    self.changed(rect)
                })
            }
        }
        required init?(coder: NSCoder) { fatalError("Created in code") }
        deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    }
}
