#if canImport(AppKit)
import Foundation
if ProcessInfo.processInfo.environment["CONSTELLATION_SPIKE"] != nil {
    LivePreviewSpike.run()  // throwaway, ticket 03
} else {
    ConstellationApp.main()
}
#else
print("Constellation is a macOS app; only ConstellationCore builds on this platform.")
#endif
