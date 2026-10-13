//
//  KeyboardDoneButton.swift
//  Dipstick
//

import SwiftUI
import UIKit

extension View {
    /// Adds a Done button above the keyboard and lets a downward swipe hide it.
    /// Number and decimal pads have no return key, so without this the keyboard
    /// only goes away by tapping into another field.
    func keyboardDoneButton() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                        )
                    }
                    .fontWeight(.semibold)
                }
            }
    }
}
