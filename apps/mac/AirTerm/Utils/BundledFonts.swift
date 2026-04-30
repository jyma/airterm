import CoreText
import Foundation

/// Registers ttf/otf font files shipped inside the SPM resource bundle so they
/// resolve via PostScript name without the user having to install anything.
/// Idempotent: register-twice is a noop (Core Text returns
/// kCTFontManagerErrorAlreadyRegistered).
enum BundledFonts {
    static func registerAll() {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil)
        else {
            DebugLog.log("BundledFonts: no ttf in resource bundle")
            return
        }

        var registered = 0
        var alreadyRegistered = 0
        var failures = 0
        for url in urls {
            var error: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if ok {
                registered += 1
            } else if let err = error?.takeRetainedValue() {
                let code = CFErrorGetCode(err)
                // 105 = kCTFontManagerErrorAlreadyRegistered — same ttf already in
                // user/system fonts, can resolve by name without our help.
                if code == 105 {
                    alreadyRegistered += 1
                } else {
                    failures += 1
                    DebugLog.log("BundledFonts: register failed code=\(code) file=\(url.lastPathComponent)")
                }
            }
        }
        DebugLog.log("BundledFonts: \(registered) registered, \(alreadyRegistered) already-registered, \(failures) failed (of \(urls.count))")
    }
}
