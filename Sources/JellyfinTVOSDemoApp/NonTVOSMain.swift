#if !os(tvOS)
@main
struct JellyfinTVOSDemoAppUnsupportedPlatform {
    static func main() {
        print("JellyfinTVOSDemoApp is only runnable on tvOS.")
    }
}
#endif
