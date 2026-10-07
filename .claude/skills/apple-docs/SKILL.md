---
name: apple-docs
description: Look up Apple's developer documentation, WWDC transcripts and sample code offline with `scrapple`, before using a system API, choosing a system feature, or claiming what macOS does. Use whenever a change touches the ScreenSaver framework, AppKit, Metal, QuartzCore (CAMetalLayer), SceneKit, Core Graphics, simd, preferences or code signing.
---

# Apple's documentation, locally

`scrapple` (Homebrew, `/opt/homebrew/bin/scrapple`) keeps Apple's developer
documentation, WWDC transcripts, sample projects and their source files in a
local SQLite index at `~/.local/share/scrapple/`, about 300,000 pages in all.
Nothing leaves the machine. It backs the `native-check-apples-documentation`
rule.

The savers deploy to macOS 14 (`DEPLOYMENT_TARGET` in each `saver.conf`,
`.macOS(.v14)` in `Package.swift`), so check a symbol's availability as well as
its signature.

## When to ask it

- **Before calling an API** whose signature, default, availability or
  behaviour you aren't certain of: a `ScreenSaverView` override, a
  `CAMetalLayer` property, a SceneKit renderer option. Don't guess; look.
- **Before building anything the system might already provide**, such as a
  timer, a preferences store or a control in an options sheet. Search first;
  the answer is usually in a framework the saver already links (`FRAMEWORKS`
  in its `saver.conf`).
- **Before stating a platform fact in a comment.** The Human Interface
  Guidelines themselves aren't in the index (it covers `/documentation`, not
  `/design`). Their conventions are in the WWDC design talks
  (search `--type talk`) and in the discussion sections of the framework docs.
- **When a doc says one thing and a saver does another:** read the doc, then
  decide.

## Commands

```sh
scrapple search "<query>" --type doc  --limit 5 --human    # API reference and articles
scrapple search "<query>" --type talk --limit 5 --human    # WWDC transcripts, with timestamps
scrapple search "<query>" --type sample --limit 3 --human  # sample projects
scrapple search "<query>" --type code_file --limit 3 --human   # a file inside a sample
scrapple -h show /documentation/screensaver/screensaverview/animationtimeinterval  # a page as Markdown
scrapple -h show <id>         # a talk or sample, by the id a JSON search returns
scrapple status               # how much is indexed, and what failed (JSON)
```

- **Output format:** without `--human` (`-h`, before the subcommand for
  `show`) the output is JSON: a search gives `id`, `title`, `type`, `url`,
  `snippet` and `score`. Use JSON when a script reads it, and `-h` when you do.
- **Queries:** a symbol name is the best query (`animateOneFrame`,
  `ScreenSaverDefaults`, `maximumDrawableCount`). A question in words works
  too, because the search is keyword and semantic together.
  - `--keyword-only` is exact and fast for a known name.
  - `--semantic-only` is for a concept you can't name.
  - A dot in a `--keyword-only` query (`ScreenSaverView.animateOneFrame`)
    crashes the search with an SQLite error. Use the separate words instead.
- **Long pages:** `show` prints the whole page, ending in `Navigate:` links
  that `show` accepts in turn. Pipe it through `head -80` or `grep -n` for the
  part you want.
- **`scrapple sync`** refreshes the index. It takes hours from empty, so the
  user runs it, not you.

## When the index says nothing

Some of what matters here is not documented anywhere: how `legacyScreenSaver`,
the sandboxed host third-party savers run in, manages a saver's lifecycle, and
how System Settings binds the Options button. `NOTES.md` records what was
measured about both ("The host never stops a screensaver", "The Options
button"). Check there before working around the host again. Otherwise, in this
order:

1. **The SDK headers**, which often carry what a page leaves out:
   `$(xcrun --show-sdk-path)/System/Library/Frameworks/ScreenSaver.framework/Headers/`.
2. **The built bundle**, loaded for real: `make verify SAVER=<name>` exercises
   what the host does on load, start, stop and restart.
3. **If neither settles it,** say so, and say what the decision rests on.

## What to do with the answer

- **Use the documented API** at its documented signature.
- **Cite the page** where a decision rests on it: one short comment with the
  page's path, e.g.
  `// /documentation/screensaver/screensaverview/animationtimeinterval`.
  A quote and a path are fine; a paragraph is not.
- **When a doc contradicts a rule in `.claude/rules/`,** raise it with the
  user. The doc is the platform's word, the rule is the project's, and only
  the user can change the rule.
