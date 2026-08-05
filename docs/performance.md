# Performance: measurements and guarantees

How Shoko's snappiness is measured, what was fixed in the 2026-06 performance
overhaul, and how to re-run the numbers. All measurements drive the real
`bin/shoko` binary on a PTY against a sandboxed 12-book library (epub, fb2,
rtf, mobi, and three PDFs from the external fixture corpus) at 220x56 — nothing is mocked,
and the latencies are what a user sees on screen.

## The harness

| Script | What it measures |
| --- | --- |
| `script/bench/menu_responsiveness_benchmark.rb` | Menu keypress→paint latency (content-verified via the details panel's `Book N of M` line), idle vs. during library pre-pagination; toast-spinner paint gaps; warmup wall time. |
| `script/bench/reader_open_benchmark.rb` | Reader time-to-first-paint and page-turn latency (content-verified via the status-bar page counter), fresh open vs. open-at-new-size with a background repagination running. |
| `script/bench/startup_menu_benchmark.rb` | Process start → first menu paint. |
| `script/bench/snappiness_benchmark.rb` | Micro-benchmarks of render/wrap/cache hot paths. |

The end-to-end scripts build a one-time sandbox (`--sandbox DIR --keep` to
reuse it) and snapshot/restore its `.cache`/`.config` between phases, so every
phase starts from the identical state and runs are comparable. Latency
detection is content-verified: a keypress only counts as painted when output
arrives that could *only* result from that keypress, so background spinner
repaints can never fake a fast result.

```bash
ruby script/bench/menu_responsiveness_benchmark.rb --sandbox /tmp/shoko-bench --keep --out menu.json
ruby script/bench/reader_open_benchmark.rb --sandbox /tmp/shoko-bench --out reader.json
```

Set `SHOKO_FIXTURES_DIR` to the extracted corpus directory, or place it at
`tmp/book-fixtures`. See [book-fixtures.md](book-fixtures.md).

## 2026-06 overhaul: background pre-pagination off the GIL

**Problem.** "Pre-paginate Library" rebuilt every cached book's page map on a
background *thread*. Pagination is CPU-bound, so under Ruby's GIL the thread
starved the menu's render loop no matter how politely it slept between
chapters: press→paint latency rose ~6x for the whole warmup (with occasional
multi-second screen freezes around uncooperative stretches), and the
politeness sleeps stretched the warmup itself to minutes.

**Fix.** The batch now runs in a separate low-priority OS process
(`bin/shoko --prepaginate-batch WxH`, niced +10) that streams JSON-line
progress over a pipe. The menu-side warmup
(`Application::Workflows::Menu::LibraryPrepaginationWarmup`) only supervises:
a worker thread blocks on the pipe (pure IO, releases the GIL), mirrors
progress into the toast, and persists the size signature when the child exits
cleanly. The OS scheduler — not the interpreter — arbitrates the CPU, so the
batch also runs flat out instead of sleeping to be polite.

Measured before/after (same sandbox, same machine, clean-HEAD baseline from a
git worktree; `idle` = no background work, `busy` = warmup running):

| Metric | Before | After |
| --- | --- | --- |
| busy press→paint p50 | 21.3 ms | 17.1 ms |
| busy press→paint p90 | 98.5 ms | **19.2 ms** |
| busy press→paint p95 | 99.4 ms | **19.4 ms** |
| busy press→paint max | 117.8 ms | **23.9 ms** |
| spinner paint gap p95 / max | 169 / 189 ms | **120 / 125 ms** (10 Hz cadence) |
| warmup wall time (12 books) | 66.6 s | **26.5 s** |
| idle press→paint p95 (control) | 17.3 ms | 22.0 ms (noise band) |

During recalculation the menu is now indistinguishable from idle, and the
recalculation finishes 2.5x sooner. Guardrail:
`spec/core/architecture/prepagination_process_isolation_spec.rb` fails any
change that moves page-map building back into the menu process.

The reader's own background repagination (opening a book at a new size) was
measured with the same harness and left unchanged: page turns stay at
p95 ≤ 57 ms while it runs, because its per-chapter builds are short and the
visible window hydrates lazily.

## 2026-06 overhaul: in-book search

Measured on the 1251-page Spengler PDF (worst case in the sandbox):

| Scenario | Before | After |
| --- | --- | --- |
| Search a cached book opened directly (`bin/shoko book.pdf`) | **crash** (`undefined method 'title' for nil`) | works |
| First search, Enter→results painted | 2693 ms (UI frozen) | 1313 ms (one-time chapter parse) |
| Repeat searches | n/a | ~395 ms |

Three defects, all in `Core::Services::InBookSearchService`:

1. **It force-wrapped the whole book.** The dynamic-page scan called
   `get_page` on every page, hydrating (wrapping) 1200+ pages on the input
   thread per search. It now scans wrapped lines only when the page map is
   already fully hydrated and otherwise uses the chapter scan — complete
   results either way, never a whole-book wrap.
2. **The chapter scan was empty for cached direct opens.** The service was
   built with `document: nil` (cached books load their document *after* the
   reader graph is built) and kept that nil forever. It now late-binds via a
   `document_provider`, the same pattern the page calculator uses.
3. **Missing chapters crashed the title lookup.** `chapter_title_for` now
   falls back to the numbered label instead of calling `.title` on nil.
