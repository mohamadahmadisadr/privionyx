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

- Text corpus: **26 fixtures, 96% fully correct.** 100% on every field except merchant, which
  is at 96%. The one open failure is item 4 below.
- Image corpus: 9 fixtures, all passing.
- Full suite green.

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

## 2. Gemma: download checksum — *blocked*

`GemmaModelManager` validates a finished download by size alone
(`downloadedSize > spec.approxBytes / 2`). A file over half the expected size reports
`.ready` and then fails at load, and the resumable background transfer makes truncation more
likely rather than less.

Needs a SHA-256 on `GemmaModelSpec` for `gemma-4-E2B-it.litertlm` (~2.6 GB) from
`litert-community/gemma-4-E2B-it-litert-lm`.

**Blocked on a decision:** a digest cannot be verified for a file that hasn't been fetched,
and inventing one is worse than the size check. Either supply the digest or approve the
download.

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

## 4. Merchant name only in the footer

Fixture `26-merchant-only-in-footer` — committed and failing. Extracts `MERCHANT COPY`.

Two problems, and fixing only the first makes the output worse:

- `MerchantExtractor.blockedTokens` knows `"customer copy"` but not `"merchant copy"`. The
  line is uppercase, short and first, so it scores 32 against a threshold of 10.
- The real name is in the footer sign-off, outside the 8-line header window. Blocking the
  token alone yields "Unknown Merchant".

A real fix needs a footer fallback when the header scores nothing — carefully, because
footers carry payment-network names that would win just as easily.

## 5. Swift 6 language mode

`SWIFT_VERSION = 5.0` while the code is annotated as though it were 6, so none of the
`@MainActor` and `Sendable` annotations are actually enforced.

Concrete hole: `NSPersistentContainer+Async.performBackgroundTask` takes a non-`@Sendable`
closure with an unconstrained `T`, and `ReceiptItem` isn't declared `Sendable`.

Two pre-existing warnings to clear on the way: `GemmaModelManager.swift:38` (main-actor
isolated static method called from a nonisolated context) and
`LiteRTGemmaReceiptAssistant.swift:30` (`shared` from a nonisolated context).

Expect this to be wide but mechanical.

## 6. `SpendingQuery` dead predicate layer — *needs a decision*

`CoreDataReceiptRepository.makePredicate` builds a complete predicate that nothing calls. All
filtering happens in memory over `PrivionyxAppState.receipts`.

**Recommendation: delete it.** Every receipt is already resident, so routing search through
Core Data would be slower per keystroke and would add a second source of truth. It only earns
its place as part of moving the dashboard, analytics *and* assistant onto paged fetches —
a far larger change than the layer itself, and one nothing currently demands.

Decide the paged-fetch question first; the layer's fate follows from it.

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
  still moving. At 92% with a known failure set, a regression floor is finally meaningful.

## Corpus shapes still uncovered

If growing the corpus again: item names wrapping to a second line, gift-card partial payment,
voided or zero-total receipts, receipts with no merchant at all, and heavily degraded OCR
beyond the single glyph-damage fixture. The last two batches returned two real bugs and then
three, so this is still finding things.
