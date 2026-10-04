//
//  AXHelpers.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift
import Cocoa

enum AXHelpers {
    private static let queue = DispatchQueue.targetingGlobal(
        label: "AXHelpers.queue",
        qos: .userInteractive,
        attributes: .concurrent
    )

    @discardableResult
    static func isProcessTrusted(prompt: Bool = false) -> Bool {
        queue.sync { checkIsProcessTrusted(prompt: prompt) }
    }

    static func element(at point: CGPoint) -> UIElement? {
        queue.sync { try? systemWideElement.elementAtPosition(Float(point.x), Float(point.y)) }
    }

    static func application(for runningApp: NSRunningApplication) -> Application? {
        queue.sync { Application(runningApp) }
    }

    static func extrasMenuBar(for app: Application) -> UIElement? {
        queue.sync { try? app.attribute(.extrasMenuBar) }
    }

    static func children(for element: UIElement) -> [UIElement] {
        queue.sync { try? element.arrayAttribute(.children) } ?? []
    }

    static func isEnabled(_ element: UIElement) -> Bool {
        queue.sync { try? element.attribute(.enabled) } ?? false
    }

    static func frame(for element: UIElement) -> CGRect? {
        queue.sync { try? element.attribute(.frame) }
    }

    static func role(for element: UIElement) -> Role? {
        queue.sync { try? element.role() }
    }

    /// Performs the semantic accessibility action for a status item whose
    /// WindowServer bounds match `windowBounds`.
    ///
    /// Some custom `NSStatusItem` views ignore synthetic mouse events even
    /// though the events are delivered successfully. `AXPress` follows the
    /// same path as a real accessibility click and works for those items.
    static func pressMenuBarItem(forPID pid: pid_t, matching windowBounds: CGRect) -> Bool {
        queue.sync {
            func performPress(on element: UIElement) -> Bool {
                do {
                    let actions = try element.actions()
                    if actions.contains(.press) {
                        try element.performAction(.press)
                        return true
                    }
                    if actions.contains(.showMenu) {
                        try element.performAction(.showMenu)
                        return true
                    }
                    return false
                } catch {
                    return false
                }
            }

            func performPressInHierarchy(startingAt element: UIElement) -> Bool {
                var current: UIElement? = element
                for _ in 0 ..< 6 {
                    guard let candidate = current else { return false }
                    if performPress(on: candidate) {
                        return true
                    }
                    current = try? candidate.attribute(.parent)
                }
                return false
            }

            // Custom status items do not always expose AXExtrasMenuBar, but
            // the system-wide element lookup can still resolve them by their
            // live WindowServer position.
            if let element = try? systemWideElement.elementAtPosition(
                Float(windowBounds.midX),
                Float(windowBounds.midY)
            ), performPressInHierarchy(startingAt: element) {
                return true
            }

            guard
                let app = Application(forProcessID: pid),
                let menuBar: UIElement = try? app.attribute(.extrasMenuBar),
                let children: [UIElement] = try? menuBar.arrayAttribute(.children)
            else {
                return false
            }

            let candidates = children.compactMap { child -> (UIElement, CGRect)? in
                guard let frame: CGRect = try? child.attribute(.frame) else {
                    return nil
                }
                return (child, frame)
            }

            let tolerance = max(windowBounds.width, 8)
            guard let target = candidates.min(by: {
                abs($0.1.midX - windowBounds.midX) < abs($1.1.midX - windowBounds.midX)
            }), abs(target.1.midX - windowBounds.midX) <= tolerance else {
                return false
            }

            return performPress(on: target.0)
        }
    }
}
