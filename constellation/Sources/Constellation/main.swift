#if canImport(AppKit)
ConstellationApp.main()
#else
print("Constellation is a macOS app; only ConstellationCore builds on this platform.")
#endif
