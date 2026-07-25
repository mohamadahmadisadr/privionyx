# Privionyx backlog

Work that is understood and not yet done. Each item says what is wrong, where it lives, and
what is already known about it, so it can be picked up without re-deriving the diagnosis.

Last updated 2026-07-24, at commit `1b31b30`.

---

## How this work has been going

**Rhythm.** One change per commit. Build, run the full suite, hand over a commit message,
stop. Don't batch several items into one commit.

**Build and test:**

```
xcodebuild test -project privionyx.xcodeproj -scheme privionyx \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .derivedData
```

Run it in the background writing to a file and poll — it has exceeded a ten-minute
foreground timeout more than once, and that has always been a slow build rather than a hang.
Always run from the repo root; a `cd` in an earlier shell call persists and will break the
next one.

**Reading corpus accuracy.** `print()` from Swift Testing never reaches the xcodebuild log,
and the simulator sandbox cannot write to host paths. The way through is a temporary test
that ends with `Issue.record("M||\(lines.joined(separator: "||"))")`, then:

```
B=$(ls -td .derivedData/Logs/Test/*.xcresult | head -1)
xcrun xcresulttool get test-results test-details --test-id "Suite/test()" \
  --path "$B" --format json | grep -o "M||[^\"]*" | head -1 | sed 's/||/\n/g'
```

Delete the temporary test before committing.

**The Graphify graph** (`graphify-out/GRAPH_REPORT.md`) is worth consulting before broad
greps, per `CLAUDE.md`. One caveat learned the hard way: it captures declared types in
signatures reliably, but misses stored-property initialisers, static member access, and
access through property chains. Treat a "who uses X" answer as a floor and confirm with grep
before concluding anything is unused.

**SourceKit diagnostics in this project are mostly false** — "No such module 'UIKit'",
"Cannot find type X in scope". `xcodebuild` is the source of truth. Don't chase them.

## Where things stand

- Text corpus: **26 fixtures, 100% fully correct**, every field at 100%.
- Image corpus: 9 fixtures, all passing.
- Full suite green, on Swift 6 language mode, with no warnings in either target.

At 100% the corpus has stopped telling us anything until it grows. See "Corpus shapes still
uncovered" — the last two batches returned two real bugs and then three.

Fixture rules worth knowing before writing more: `lineItemSum` must be `null` on text
fixtures, because line items need geometry and the raw-text path returns `[]` by design. When
a new fixture fails, fix the parser rather than softening the fixture — and if the ground
truth is genuinely ambiguous, say so in the fixture's `notes` and pick the defensible reading.

---

## 1. Gemma: increased-memory-limit entitlement — *done, unverified on hardware*

`privionyx/privionyx.entitlements` now carries
`com.apple.developer.kernel.increased-memory-limit`, wired to both app build configurations
via `CODE_SIGN_ENTITLEMENTS`. Automatic signing adds the capability to the profile without
review. Confirmed applied: the simulator build's `privionyx.app-Simulated.xcent` contains the
key (the plain `.xcent` is empty on simulator because there is no profile to filter against —
that is expected, not a failure).

**The mmap question, answered.** LiteRT-LM maps the file rather than reading it:
`litert_lm_lib.cc:101` opens the model path as a `ScopedFile`, `litert_lm_loader.cc` maps each
section through `MemoryMappedFile::Create`, and
`memory_mapped_file_posix.cc:114` is `mmap(..., PROT_READ | PROT_WRITE, MAP_PRIVATE, ...)`
followed by `madvise(MADV_DONTNEED)` on Apple platforms specifically. The flatbuffer is then
parsed in place — `model_resources_litert_lm.cc:73` hands the mapped `BufferRef` straight to
`Model::CreateFromBuffer`, no copy. So the weight pages start clean and file-backed, and clean
file-backed pages are not charged to `phys_footprint`.

That makes the entitlement cheap insurance rather than the load-bearing fix, and it is still
worth having: the mapping is `PROT_WRITE`, so anything the runtime mutates in place becomes a
dirty copy-on-write page at full cost; the `.gpu` backend uploads weights into Metal buffers,
which *are* charged to the process; and the KV cache and activations are anonymous throughout.

**Still unknown, and only hardware will say:** how much of the 2.6 GB actually ends up dirty
or in GPU buffers under the Metal backend. Evidence the hardware is capable: Google's Edge
Gallery runs the same model on an iPhone 15.

## 2. Gemma: download checksum — *done*

It was never blocked. The digest did not need the file: Hugging Face publishes the SHA-256 of
every LFS-backed file in its repository metadata, and
`GET /api/models/{repo}/tree/{revision}` returns it as `lfs.oid` for a few kilobytes of JSON.

`gemma-4-E2B-it.litertlm` is `181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c`,
exactly 2,588,147,712 bytes — not the 2,600,000,000 the spec had been guessing.

Three changes followed from having an exact figure:

- `approxBytes` became `expectedBytes` and the install check became equality. The old
  `> approxBytes / 2` would have passed a file 1.3 GB short.
- The digest is verified once, on install, streamed a megabyte at a time inside the download
  delegate — the only moment the file can still be rejected before the user has been told it
  is ready. Never on launch: hashing 2.6 GB on every appearance of Settings would cost seconds
  to learn nothing.
- `remoteURL` is pinned to revision `9262660a`, not `main`. A digest describes one set of
  bytes; a branch that moves would turn every download in the shipped app into a verification
  failure.

If the model is ever changed or a second one added, the digest and the size come from that
same endpoint — there is no reason to fetch gigabytes to learn them.

## 3. Glyph repair misses an O beside the decimal point — *done*

Fixture `24-faded-print-glyph-damage` passes. `ReceiptTextSanitizer.repairedDigitGlyphs` is
now shared with `DateExtractor`, which no longer keeps its own copy.

Not done the way this entry proposed. Lifting `DateExtractor`'s `(?<=\d)(o|O)\b` in verbatim
would have turned `H2O` into `H20` — a word boundary fires against a space as readily as
against a decimal point, and the O ends the token in `H2O` exactly as it does in `7.5O`. What
tells them apart is the rest of the token, so the edge repair is token-scoped: a
whitespace-delimited token made only of digits, `oOlI` and numeric punctuation, carrying at
least one surviving digit, is a figure and gets repaired; anything with another letter in it
is left alone. The between-digits rules stayed, because they run over the whole line and still
reach a `1O2` buried inside `REF#1O2`.

Covered by `ReceiptTextSanitizerTests`, which pins the tokens that must *not* change
(`12oz`, `H2O`, `NO5`, separator rows) as firmly as the ones that must.

## 4. Merchant name only in the footer — *done*

Fixture `26-merchant-only-in-footer` passes. `"merchant copy"` joined `"customer copy"` in
`blockedTokens`, and `MerchantExtractor.signOffMerchant` reads the footer when the letterhead
has produced nothing.

The footer is not scanned freely — that was the risk this entry named, and it is real:
`INTERAC CHIP` and `APPROVED` both read as convincingly like a name as the vendor does. The
fallback is anchored to the sign-off instead. A greeting that trails off on `AT` or `CHEZ` is
a sentence whose object is the next line, and that next line is the only one it will consider.
A plain `THANK YOU` introduces nobody and yields nothing. `"approval"` widened to `"approv"`
on the way, so the terminal's `APPROVED` is blocked as well.

The per-line rules moved into a shared `merchantCandidate`; position scoring stayed behind in
`heuristicMerchant`, since it only means anything read from the top.

Covered by `MerchantExtractorTests`, weighted toward the cases where the fallback must stay
silent. `restaurant-primerib`, the image fixture that carries no merchant anywhere, still
reports none.

## App Store submission — *privacy manifest done, rest open*

`privionyx/PrivacyInfo.xcprivacy` ships at the root of the app bundle, and
`ITSAppUsesNonExemptEncryption` is `NO` in the generated Info.plist (verified in the built
product, not just the build setting).

The manifest was the one automated blocker: since spring 2024 App Store Connect rejects an
upload that calls a required-reason API without declaring it, by email, before a human sees
it. Three apply here and each names a real call site — `attributesOfItem` for the model file
(`C617.1`), `volumeAvailableCapacityForImportantUsage` before the download (`E174.1`), and
`UserDefaults` for the budget, merchant rules and migration flags (`CA92.1`). Boot time and
active keyboards are not touched. Nothing is collected and nothing tracks, so those arrays are
empty and honestly so.

Still open before a submission:

- **A 2.6 GB download over cellular.** `URLSessionConfiguration.background` allows it by
  default. `allowsExpensiveNetworkAccess = false` would confine it to Wi-Fi. This is a product
  decision, not a bug — but a user who spent their data plan on it will say so in a review.
- **Gemma's licence.** The weights are Apache-2.0 and ungated, but Google's Gemma Terms of Use
  travel with the model and want attribution. Where that notice belongs on screen is unsettled.
- **The screenshot problem.** Review runs on a device with no receipts and no model
  downloaded. Whatever a reviewer sees on first launch is what the app is judged on.

## 5. Swift 6 language mode — *done*

`SWIFT_VERSION = 6.0` on all four configurations. Clean build, no warnings in either target,
full suite green, both corpora still 100%.

Wide and mechanical as expected — 48 files — but two things mattered more than the annotations,
and the first is the reason this item existed at all.

**The project's default isolation was pointed the wrong way, silently.**
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` was already set, so every unannotated declaration
was nominally confined to the main actor — including `ReceiptManagedObject`,
`ReceiptLineItemCoder`, `ReceiptFileStorage` and the entire parsing pipeline. All of it is
reached from Core Data's private queue or from `Task.detached`. Under Swift 5 the isolation was
assigned and then ignored, so the code worked. Turning enforcement on is what surfaced it. The
data and domain layers are now explicitly `nonisolated`, which is what they always were in fact.

**`performBackgroundTask` was the hole this entry named, and it was load-bearing.** The closure
is now `@Sendable` with `T: Sendable`, and that is what forced the above: once the boundary was
real, everything crossing it had to say what it was. The constraint's actual job is to make
returning an `NSManagedObject` a compile error rather than an occasional crash. The two closures
that captured `self` for a single field now capture `[fileStorage]`.

Along the way: `CoreDataStack.storeLoadFailure` became a `let` — the loading steps are static
now, so it is decided once in `init` — which shrinks that type's `@unchecked Sendable` claim to
the container alone. `NSMergeByPropertyObjectTrumpMergePolicy`, a global `var` of type `Any`,
gave way to `NSMergePolicy.mergeByPropertyObjectTrump`. `FileManager`, `UserDefaults` and
`MLModel` — thread-safe by documentation, `Sendable` by nothing — are `nonisolated(unsafe)`
where they are held.

**The one asserted guarantee is `@preconcurrency import LiteRTLM`.** The package is
`swift-tools-version: 5.9` with no concurrency settings, and its API cannot be satisfied
otherwise: `Engine` is an actor whose `createConversation()` returns a plain class, and
`Conversation.sendMessage` is a nonisolated `async` method, so a `Conversation` must leave one
isolation domain to be created and enter another to be used. Neither crossing is annotatable
from this side. What makes it hold is on this side — one conversation at a time, reached only
through the `@MainActor` `LiteRTGemmaReceiptAssistant`. Drop the attribute when the package
ships Swift 6 annotations.

The two warnings this entry expected to clear sat inside `#if canImport(LiteRTLM)` and are
gone; that boundary is the `@preconcurrency` import's business now.

## 6. `SpendingQuery` dead predicate layer — *done, deleted*

Deleted, and further than this entry proposed. `makePredicate` was the visible half; the
parameter feeding it was dead too. Every call site — three use-case callers and six tests —
passed `nil`, so `SpendingQuery` itself had no consumers once the predicate went. All of it is
gone: the type, the parameter, and the predicate builder. `fetchReceipts()` now takes nothing
and the protocol says why.

Paged fetches were the decision this hinged on, and the answer is no. Every receipt is already
resident in `PrivionyxAppState.receipts`, so a store-side predicate would be slower per
keystroke and would be a second answer to a question already answered. It only earns its place
as part of moving the dashboard, analytics *and* assistant onto paged fetches together — far
larger than the layer itself, and nothing currently demands it. Should that day come, this is
a page of straightforward `NSPredicate` construction to write back, against a much clearer
starting point than a builder nobody called.

---

## Smaller things, noticed and deliberately left

- **`DashboardViewModel` filters `amount > 0`** in three display spots (category breakdown,
  lowest-spending category, peak bucket). Now that refunds parse negative, a category whose
  net goes negative is omitted rather than shown as a credit. Noticed while fixing refunds,
  not chosen.
- **`bottomAmountScore` still starts from dollar magnitude** (image path). That is the same
  scale-dependence removed from the text path, but no fixture demonstrates a failure and the
  term is load-bearing as a tiebreaker in `extractValueFromStructuredTotals`.
- **`ACCOUNT BALANCE 1250.00` can outrank `TOTAL 420.00`** — `"balance"` earns +40 as a
  positive signal, intended for `"balance due"`. No fixture reproduces it; tuning the token
  list against an invented example was declined.
- **`CoreMLReceiptExtractionService.parseAmount` duplicates `AmountExtractor`.** Dormant —
  no `.mlmodelc` ships, so the Core ML path never runs today.
- **The image corpus is 9 fixtures against 26 text ones.** The end-to-end path is far less
  measured than parsing is.
- **The corpus measures rather than gates.** Thresholds were deferred while the numbers were
  still moving. They have stopped: both corpora are at 100% with no known failures, so a
  regression floor now costs nothing to set and is the only thing that would catch a
  regression at all.

## Corpus shapes still uncovered

If growing the corpus again: item names wrapping to a second line, gift-card partial payment,
voided or zero-total receipts, receipts with no merchant at all, and heavily degraded OCR
beyond the single glyph-damage fixture. The last two batches returned two real bugs and then
three, so this is still finding things.
