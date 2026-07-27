#if canImport(GoogleMobileAds)
import GoogleMobileAds
import SwiftUI
import UIKit

/// The AdMob banner, behind `BannerAdProviding` so no screen imports the SDK.
///
/// Guarded by `canImport` so the app still builds if the package is ever removed — the
/// protocol's `NoBannerAds` takes over and the ad slots collapse to nothing.
@MainActor
final class GoogleBannerAdProvider: BannerAdProviding {
    /// The AdMob unit for this app's banner. Release builds only — see `adUnitID`.
    static let liveAdUnitID = "ca-app-pub-7526873529830557/8683181042"

    /// Google's public test banner unit.
    ///
    /// Used for every build that is not a Release build, and not negotiable: requesting live
    /// ads from a development build, and especially tapping one, is what gets an AdMob
    /// account suspended for invalid traffic. The account is harder to get back than the
    /// afternoon it saves.
    static let testAdUnitID = "ca-app-pub-3940256099942544/2934735716"

    private let adUnitID: String
    private static var hasStartedSDK = false

    var isConfigured: Bool { true }

    init(adUnitID: String = GoogleBannerAdProvider.defaultAdUnitID) {
        self.adUnitID = adUnitID
        Self.startSDKIfNeeded()
    }

    static var defaultAdUnitID: String {
        #if DEBUG
        testAdUnitID
        #else
        liveAdUnitID
        #endif
    }

    /// Starts the SDK once per process. Cheap to call again; it just returns.
    private static func startSDKIfNeeded() {
        guard hasStartedSDK == false else { return }
        hasStartedSDK = true
        MobileAds.shared.start()
    }

    /// One banner per placement, built once and reused.
    ///
    /// Held here rather than by the SwiftUI view because the screens that show ads build
    /// their content lazily: the view is torn down whenever it scrolls out of sight, and a
    /// fresh `BannerView` each time would mean a fresh ad request each time.
    private var banners: [AdPlacement: BannerView] = [:]

    func preferredHeight() -> CGFloat {
        Self.adSize(width: Self.availableWidth).size.height
    }

    func banner(placement: AdPlacement, onHeightChange: @escaping (CGFloat) -> Void) -> AnyView {
        AnyView(
            BannerAdRepresentable(
                view: bannerView(for: placement),
                onHeightChange: onHeightChange
            )
        )
    }

    private func bannerView(for placement: AdPlacement) -> BannerView {
        if let existing = banners[placement] { return existing }

        let view = BannerView(adSize: Self.adSize(width: Self.availableWidth))
        view.adUnitID = adUnitID
        view.backgroundColor = .clear
        banners[placement] = view
        return view
    }

    /// Google's inline adaptive size — the format meant for a banner that scrolls with the
    /// content rather than being pinned to an edge.
    ///
    /// Capped well below what the format allows. Left uncapped it will happily return a
    /// banner several hundred points tall, which is a different thing from the strip this
    /// app agreed to show.
    static func adSize(width: CGFloat) -> AdSize {
        inlineAdaptiveBanner(width: max(width, 1), maxHeight: 90)
    }

    /// The width a full-bleed banner gets, read from the window rather than passed down from
    /// SwiftUI: the slot that hosts this is height-constrained, and a `GeometryReader` inside
    /// it reports a height of zero, which is exactly the state the SDK refuses to load into.
    static var availableWidth: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first { $0.activationState == .foregroundActive }?.keyWindow
            ?? scenes.first?.keyWindow
        return window?.bounds.width ?? UIScreen.main.bounds.width
    }

    /// A request that asks for non-personalized ads.
    ///
    /// `npa=1` is what keeps this app off the tracking path entirely: no IDFA, so no App
    /// Tracking Transparency prompt, so `NSPrivacyTracking` stays false and the privacy label
    /// does not have to say "Data Used to Track You". It costs some revenue. That was the
    /// deliberate trade.
    static func nonPersonalizedRequest() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        return request
    }
}

/// Hosts a `BannerView` in SwiftUI and reports the height it actually ends up occupying.
private struct BannerAdRepresentable: UIViewRepresentable {
    /// Supplied by the provider, which owns it — this view is a window onto an ad that
    /// outlives any one appearance of the screen showing it.
    let view: BannerView
    let onHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightChange: onHeightChange)
    }

    func makeUIView(context: Context) -> BannerView {
        view.delegate = context.coordinator
        view.rootViewController = Self.rootViewController
        context.coordinator.loadIfNeeded(view, width: GoogleBannerAdProvider.availableWidth)
        return view
    }

    func updateUIView(_ view: BannerView, context: Context) {
        // Rotation and iPad multitasking change the available width, and an adaptive banner
        // is sized from that width. Reloading only when it actually changed keeps this from
        // firing a fresh ad request on every layout pass.
        let width = GoogleBannerAdProvider.availableWidth
        guard context.coordinator.loadedWidth != width else { return }
        view.adSize = GoogleBannerAdProvider.adSize(width: width)
        context.coordinator.loadIfNeeded(view, width: width)
    }

    /// The view controller ads present from when tapped. Found rather than injected: the app
    /// is a single scene, and threading a controller reference through SwiftUI to satisfy one
    /// SDK property would put UIKit in every view that shows an ad.
    private static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?
            .rootViewController
    }

    @MainActor
    final class Coordinator: NSObject, BannerViewDelegate {
        private let onHeightChange: (CGFloat) -> Void
        private(set) var loadedWidth: CGFloat?

        init(onHeightChange: @escaping (CGFloat) -> Void) {
            self.onHeightChange = onHeightChange
        }

        /// Requests an ad, unless this banner already has one for this width.
        func loadIfNeeded(_ view: BannerView, width: CGFloat) {
            guard width > 0, loadedWidth != width else { return }
            loadedWidth = width
            view.load(GoogleBannerAdProvider.nonPersonalizedRequest())
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            // Only now does the slot take up space. Reserving it before the ad arrives — or
            // when none ever does — would leave a blank strip pushing the app's own content
            // off screen for nothing.
            onHeightChange(bannerView.adSize.size.height)
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            // No fill is routine, not an error worth telling the user about: the slot simply
            // collapses and the app looks like it has no ads.
            onHeightChange(0)
        }
    }
}
#endif
