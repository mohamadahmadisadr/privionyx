# Shipping Privionyx

Everything between a green build and a live App Store listing. Written for the state of the
repository as of the first release (bundle id `dev.sadr.privionyx`, version 1.0).

Privionyx is an iOS app. Google Play does not apply to it — there is no Android target, and
nothing in this repository could be submitted there. The equivalent gate is Apple's **App
Store Review Guidelines**, which is what the audit below is against.

---

## 1. Where the app stands

### Already in order

| Requirement | Where it lives |
| --- | --- |
| App icon, all three appearances | `Assets.xcassets/AppIcon.appiconset` (source: `Tools/MakeAppIcon.swift`) |
| Camera + photo library usage strings | `INFOPLIST_KEY_NS*UsageDescription` in build settings |
| Privacy manifest, incl. required-reason APIs | `privionyx/PrivacyInfo.xcprivacy` |
| Export compliance declaration | `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` |
| Third-party attribution + full licence text | Settings → Acknowledgements |
| Increased memory limit entitlement | `privionyx.entitlements` (no review needed) |
| Launch screen | `INFOPLIST_KEY_UILaunchScreen_Generation = YES` |
| Version shown in-app | Settings → About → Version |
| No debug leftovers | No `TODO`, `print(`, `try!`, or `http://` in app sources |
| Sample data cannot ship enabled | `PrivionyxSampleData.isRequested` is `#if DEBUG` only |

Before submitting, buy the upgrade once against **Apple's sandbox** — run the
**`privionyx (Sandbox)`** scheme on a device. The local StoreKit configuration file proves
nothing about the product record in App Store Connect, and the sandbox is the same
environment the reviewer will buy in. `SANDBOX.md` is the walkthrough.

### Decide before you submit

- **Deployment target is iOS 26.4.** That is a very narrow slice of devices — anyone on
  26.0–26.3 cannot install the app. If nothing actually requires 26.4, dropping to 26.0
  costs nothing and widens the audience considerably. This is a business call, not a
  review risk.
- **`MemoryFootprintTests/fullResolutionCaptureStaysWithinBudget` fails in full-suite
  runs** (it passes alone; it is sensitive to memory pressure from tests running in
  parallel). Xcode Cloud runs the full suite, so this will fail every build until it is
  either made robust or excluded from the CI test plan. Pre-existing, unrelated to any
  recent feature work.
- **iPad.** `TARGETED_DEVICE_FAMILY = "1,2"` promises iPad support, and reviewers test on
  iPad. Run it on an iPad simulator once end-to-end. If the layout does not hold up, ship
  iPhone-only (`TARGETED_DEVICE_FAMILY = "1"`) rather than shipping a broken iPad build —
  guideline 2.1 rejections cite exactly this.

### The one thing a reviewer might trip over

The optional Gemma download is **2.6 GB**. Reviewers work over shared office Wi-Fi against a
deadline, and an app that appears to hang on a multi-gigabyte transfer gets rejected under
guideline 2.1 as incomplete.

The app already defends against this: the built-in rule-based assistant works offline
immediately, the download is user-initiated, and it waits for Wi-Fi. What the reviewer needs
is to be *told* — see the review notes in §4. Model weights are data, not executable code, so
guideline 2.5.2 is not engaged.

---

## 2. Xcode Cloud

There is no `xcloud` CLI. Xcode Cloud is configured in Xcode (or the App Store Connect web
UI); the only part that lives in the repository is `ci_scripts/`, which is done.

### What the repository now provides

- **`privionyx.xcodeproj/xcshareddata/xcschemes/privionyx.xcscheme`** — Xcode Cloud can only
  build a *shared* scheme, and this project had none at all (Xcode was autocreating a
  private one). Without this file, no workflow can be created.
- **`ci_scripts/ci_post_clone.sh`** — the project references LiteRT-LM as a *local* package
  at `LiteRT-LM/LiteRT-LM`, and that directory is gitignored (1.2 GB, its own nested `.git`).
  Every Xcode Cloud build starts from a fresh clone, so without this script package
  resolution fails before anything compiles. The script clones the pinned tag `v0.13.1`.

Xcode Cloud runs `ci_post_clone.sh` automatically if it is executable and committed — both
are true. It must stay at the repository root under `ci_scripts/`.

### Creating the workflow

1. **Xcode → Product → Xcode Cloud → Create Workflow.** Sign in with an Apple ID holding
   Admin or App Manager on the team. Requires a paid Apple Developer Program membership;
   25 compute hours/month are included.
2. **Grant source access.** Point it at `github.com/mohamadahmadisadr/privionyx` and install
   the Xcode Cloud GitHub app when prompted. The repository must be reachable by Apple —
   a private repo is fine once the app is installed.
3. **Start condition:** *Branch Changes* → `main`, any file. That is the "build on every
   push" part of the ask. Add a second condition for pull requests if you want PR checks.
4. **Environment:** Xcode 26.x (match what you build with locally — the deployment target is
   26.4), macOS latest. Leave "Clean" off; caching is what keeps builds inside the free tier.
5. **Actions:**
   - *Build* — scheme `privionyx`, configuration Release.
   - *Test* — destination iOS Simulator; see the `MemoryFootprintTests` caveat in §1 first.
   - *Archive* — iOS, Release. Only add this once §3 is done and the app record exists.
6. **Post-action:** *TestFlight Internal Testing* on the archive, so every green build on
   `main` lands in TestFlight. Add *Notify* for a Slack channel or email.
7. **Build numbers:** let Xcode Cloud manage them (it sets `CI_BUILD_NUMBER`), or App Store
   Connect will reject the second upload for reusing build `1`. `CURRENT_PROJECT_VERSION` in
   the project stays as the local default.

### Verifying it

The first run is the test. If it fails during "Resolve Packages", the post-clone script did
not do its job — check the log for `Cloning LiteRT-LM v0.13.1` and confirm the tag still
exists upstream.

---

## 3. Creating the app in App Store Connect

Do this once, before the first archive is uploaded.

**Prerequisites:** paid Apple Developer Program membership, and the bundle id registered.

### Register the bundle id

1. [developer.apple.com](https://developer.apple.com/account) → *Certificates, Identifiers &
   Profiles* → **Identifiers** → **+**.
2. *App IDs* → *App*. Description: `Privionyx`. Bundle ID: **Explicit**,
   `dev.sadr.privionyx` — it must match `PRODUCT_BUNDLE_IDENTIFIER` exactly.
3. Capabilities: enable **Increased Memory Limit** (the app's entitlement). Nothing else is
   used — no push, no iCloud, no App Groups.
4. Register.

### Create the app record

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **+** → *New App*.
2. Platform **iOS**; Name (30 chars, must be unique across the store — have a fallback
   ready); primary language; the bundle id from above; **SKU** (any internal string, e.g.
   `privionyx-ios-1`); full access.

### Fill in the listing

- **Privacy Policy URL — mandatory.** Every app needs one, even one that collects nothing.
  GitHub Pages is sufficient; it must be a live URL at submission or the build cannot be
  submitted.
- **Support URL — mandatory.** A repository README or a contact page is enough.
- **Category:** Finance (primary). Productivity is a reasonable secondary.
- **Age rating:** answer the questionnaire honestly; this app lands at 4+.
- **Screenshots:** required for 6.9" iPhone. If you ship iPad support you must also supply
  13" iPad screenshots — another reason to settle the iPad question first. Take them on a
  simulator with sample receipts loaded (`-privionyxSampleData` in a Debug build) so the
  dashboard and assistant have something to show.
- **Description / keywords / promotional text:** describe on-device processing plainly.
  Do not name other apps and do not claim compliance with regulations the app has not been
  audited against.

### The in-app purchase

The app sells one non-consumable, `dev.sadr.privionyx.removeads`. Until it exists
here, **the store returns nothing** — in the sandbox, to a reviewer, and to every user — and
the app correctly reports "The upgrade isn't available on this device right now."
`Privionyx.storekit` is only a local mirror of this record; nothing in it reaches Apple.

**First, the Paid Applications Agreement.** App Store Connect → **Business** → *Agreements*.
Sign it, and complete the **tax forms and banking details**. Until the agreement is *Active*,
`Product.products(for:)` returns an empty array with no error, in every environment including
sandbox. This is the single most common reason a correctly written purchase looks broken, and
it takes days to clear if the tax forms are wrong — start it before you need it.

**Then create the product.** App Store Connect → your app → **Monetization → In-App
Purchases** → **+**.

| Field | Value | Why it matters |
| --- | --- | --- |
| Type | **Non-Consumable** | Bought once, restorable forever. A consumable would break restore, and subscriptions carry obligations this app does not want. |
| Reference Name | `Remove Ads` | Internal only. |
| Product ID | `dev.sadr.privionyx.removeads` | Must match `PrivionyxProduct.removeAds` **character for character**. A mismatch is silent — an empty product list, exactly like an unsigned agreement. |
| Price | the $4.99 tier | Set one price point; Apple derives every other storefront. The app reads `displayPrice` and never formats currency itself. |
| Display Name | `Remove Ads` | Shown in the App Store's purchase sheet, not by this app. |
| Description | `Removes banner ads everywhere in Privionyx. One-time purchase.` | |
| Family Sharing | **Off** | Must agree with `"familyShareable": false` in `Privionyx.storekit`, or the local loop and the real one disagree about what a purchase gives. |

**The review screenshot is mandatory.** Upload one of the Remove Ads sheet (1284×2778 from a
6.9" simulator is fine). Without it the product sits at *Missing Metadata* and cannot be
submitted at all — it is not a warning, it is a hard block.

**Attach it to the version.** On a first submission the purchase is reviewed *alongside* the
app: open the version in App Store Connect and add the purchase under **In-App Purchases**.
Skipping this is the classic mistake — the app ships, the product does not, and every user
sees the upgrade as unavailable.

A newly created product can take a few hours to start returning in the sandbox. An empty
result immediately after creating it is not necessarily a bug.

### App Privacy (the nutrition label)

App Store Connect → your app → **App Privacy** → Get Started.

Answer **"No, we do not collect data from this app."** That is accurate: receipts are parsed
on-device, the assistant runs locally, and the only outbound request is an unauthenticated
GET for a public model file. This must agree with `PrivacyInfo.xcprivacy`, and it does.

### First upload

Archive from Xcode (or let the Xcode Cloud archive action do it) → Distribute → App Store
Connect. Export compliance is answered automatically by
`ITSAppUsesNonExemptEncryption = NO`, so no upload prompt appears.

---

## 4. App Review notes

Paste into *App Review Information → Notes*. This is the field that prevents the most
likely rejection.

```
Privionyx scans receipts and answers questions about spending entirely on-device.
No account, no sign-in, and no server: there is nothing to give you credentials for.

To see the app with data in it, open the Receipts screen and tap "Load sample
receipts" — this adds ten example receipts you can delete again from
Settings → Remove sample receipts.

About the optional AI model download:
Settings offers an optional 2.6 GB on-device Gemma model. It is NOT required to
review the app. The assistant works immediately with the built-in offline engine,
which is the default. The download is user-initiated, waits for Wi-Fi, and can be
cancelled at any time. Please do not wait on it.

The model file is data (neural network weights), not executable code, downloaded
from a public Hugging Face repository under the Apache 2.0 licence. Attribution
and the full licence text are in Settings → Acknowledgements.

Camera access is used only to photograph paper receipts. Photo library access is
used only to import an existing receipt image. Neither image ever leaves the device.

About the in-app purchase:
There is one non-consumable, "Remove Ads" (dev.sadr.privionyx.removeads).
It removes the banner ads and nothing else — no feature of the app is behind it.

To test it: Settings → Ads → Remove Ads, or the "Remove ads" link under any
banner. "Restore Purchases" sits next to it on the same screen and also in
Settings → Ads, as required by guideline 3.1.1.

Your purchase runs against the sandbox and is not charged.
```

**The reviewer's purchase runs in the sandbox automatically.** Nothing needs to be enabled,
and no test account needs handing over — App Review's own account buys in the sandbox and is
never charged. What their purchase actually depends on is entirely on your side:

- the Paid Applications Agreement being *Active*,
- the product existing with a **matching identifier**,
- the product **attached to the version under review**,
- a **restore path** reachable without buying first (Settings → Ads → Restore Purchases —
  present, and its absence is a certain 3.1.1 rejection).

Verify all four by buying it yourself in the sandbox first — see `SANDBOX.md`. A reviewer
hitting "the upgrade isn't available" is a rejection, and it is the same failure the sandbox
would have shown you a week earlier.

---

## 5. Before every subsequent release

- Bump `MARKETING_VERSION`; let Xcode Cloud handle the build number.
- Re-check `PrivacyInfo.xcprivacy` if any new API or dependency was added.
- If the Gemma model revision changes, update `expectedBytes` and `sha256` in
  `GemmaModelSpec` together — they describe one specific set of bytes.
- Confirm the Acknowledgements screen still matches what the upstream repository declares
  (the download source currently declares Apache-2.0 and is ungated; the wider Gemma family
  ships under Google's Gemma Terms, so a re-tag upstream would need the screen updated).
