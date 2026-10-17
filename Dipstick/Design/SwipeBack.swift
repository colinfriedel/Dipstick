//
//  SwipeBack.swift
//  Dipstick
//

import UIKit

/// Screens use their own back button (design spec), which hides the system
/// navigation bar and with it the edge-swipe-to-go-back gesture. This turns
/// the gesture back on for every pushed screen.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
