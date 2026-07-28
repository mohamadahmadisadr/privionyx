# Testing the purchase

There are two ways to run the purchase, and they prove different things.

| | Scheme | What it proves |
| --- | --- | --- |
| **Local StoreKit** | `privionyx` | The app's own code paths. Purchases never leave the machine. |
| **Apple's sandbox** | **`privionyx (Sandbox)`** | The real product record, the real purchase sheet — the same environment the App Store reviewer buys in. |

Nothing here is in the app. Both are schemes; the shipping binary contains no test surface of
any kind, and there is nothing a user can switch.

---

## The `privionyx (Sandbox)` scheme

Select it in Xcode's scheme menu and run. It is the `privionyx` scheme with the
`Privionyx.storekit` reference removed, so StoreKit stops faking it and talks to Apple.
Archiving is disabled on it — it is for running, not for shipping.

> **It has to be a physical device.** The simulator cannot sign in to a Sandbox Apple Account,
> so running this scheme there gets an empty product list and the app says the upgrade is
> unavailable. That is the simulator, not a bug.

### Before it can work

Two things, both outside the code, and each of which makes a perfectly correct app look
broken in exactly the same way — an empty product list and "The upgrade isn't available on
this device right now."

1. **The Paid Applications Agreement must be *Active***, tax forms and banking included.
   Until then `Product.products(for:)` returns an empty array with no error. This is the most
   common cause by a wide margin, and it takes days to clear if the tax details are wrong.
2. **The product must exist in App Store Connect** — Non-Consumable,
   `dev.sadr.privionyx.removeads`, matching character for character, with a review
   screenshot uploaded.

Both are in `RELEASE.md` §3 → *The in-app purchase*, with every field and why it matters.

A newly created product can take a few hours before it starts returning in the sandbox. An
empty result right after creating it is not necessarily wrong.

### Running it

1. Create a Sandbox Apple Account: App Store Connect → **Users and Access → Sandbox → Test
   Accounts**. Use an address you control that has never been an Apple ID.
2. On the device: **Settings → Developer → Sandbox Apple Account**, and sign in *there*. Not
   in the App Store proper — signing a sandbox account into the real App Store loses it.
3. Run the `privionyx (Sandbox)` scheme.
4. Buy the upgrade — Settings → Ads → Remove Ads, or the "Remove ads" link under any banner.
   A sandbox purchase is free but otherwise entirely real: the actual product identifier, the
   App Store's own purchase sheet, `Transaction.currentEntitlements`. The banners should
   disappear everywhere the moment it completes.
5. Delete the app, reinstall, and tap **Restore Purchases**. That is the guideline 3.1.1 path,
   and the one nothing else tests.

**A sandbox account can own a non-consumable only once.** To walk the first-time purchase
again, clear the account's history under **Settings → Developer → Sandbox Apple Account →
Manage → Clear Purchase History**, or use a fresh account.

---

## What the reviewer sees

The same thing, in the same environment. **App Review buys in the sandbox automatically** —
never charged, no test account to hand over, nothing to switch on.

So a reviewer's purchase succeeds exactly when yours does, and fails for the same four
reasons:

- the Paid Applications Agreement is not Active,
- the product identifier does not match,
- the product was not **attached to the version under review** — the classic first-submission
  mistake: the app ships, the product does not, and every user sees the upgrade as
  unavailable,
- there is no restore path (there is one — Settings → Ads → Restore Purchases; its absence is
  a certain 3.1.1 rejection).

Buying it once yourself in the sandbox checks all four at the same time. `RELEASE.md` §4 has
the review notes to paste in.

---

## TestFlight

TestFlight builds use the sandbox too, and with the **tester's own Apple ID** — no Sandbox
Apple Account needed. It is the easiest way to have someone else exercise the purchase, and
it is closer to what the reviewer runs than any Debug build, being the Release binary.

---

## The local StoreKit file — the fast loop

Run the plain **`privionyx`** scheme. `Privionyx.storekit` is applied: purchases complete
instantly, cost nothing, and never reach Apple.

- **Debug → StoreKit → Manage Transactions** is where you delete a purchase to run the flow
  again, and where failures, Ask to Buy, and refunds are simulated.
- Editing `Privionyx.storekit` changes the price and the localisation.
- `"familyShareable": false` in that file must agree with App Store Connect, or the two loops
  disagree about what a purchase gives.

What it does **not** prove: that the product exists, that its identifier matches, that it is
approved, or that the agreement is signed. Every one of those is a real way for the shipping
app to have nothing to sell while this loop stays green — which is what the Sandbox scheme is
for.
