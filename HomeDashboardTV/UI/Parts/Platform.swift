import CoreText
import SwiftUI

/// What differs between the TV and the Mac screensaver, kept here so the layouts compile for
/// both: the colour and font types (both toll-free bridged to their Core Graphics and Core Text
/// types, which is what the drawing uses underneath), and where the resources come from.
#if canImport(UIKit)
import UIKit

typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
#else
import AppKit

typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
#endif

/// Where the layouts' resources (the fonts, the moon photo, the demo week, the shaders) come
/// from: the app's own bundle on tvOS, and the saver bundle on the Mac, where `Bundle.main` is
/// the screensaver host and holds none of them. The saver sets it before anything loads.
enum PlatformBundle {
    static var resources: Bundle = .main

    /// Registers the bundled faces with Core Text, for the Mac, where a bundle has no
    /// `UIAppFonts`. Once per process; a face already registered is left as it is.
    static func registerFonts() {
        let urls = ["ttf", "otf"].flatMap { resources.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}

extension Font {
    /// A face from *attributes* (a name or family, variation axes, features), through Core Text
    /// so the same descriptor works on both platforms.
    static func descriptor(_ attributes: [CFString: Any], size: CGFloat) -> Font {
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }
}
