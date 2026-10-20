# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

The sqlite3 gem's API (v2.10 surface: `Database`, `Statement`, `ResultSet`, pragmas, error classes) in pure Ruby over Fiddle and the system `libsqlite3`. No C extension. Two consumers that must both work:

- **MRI** (Ruby >= 3.3) and **JRuby** (10+, via fiddle's FFI backend) — plain gem.
- **rb2go** ([jtarchie/ruby2go](https://github.com/jtarchie/ruby2go)) — a Ruby→Go compiler that vendors this repo at `gems/sqlite3-fiddle` and answers `require "sqlite3"` with it. The compiled program's output must match MRI's.

"decision N" comments refer to ruby2go's `docs/design.md`, not anything in this repo.

## Commands

```sh
bundle exec rake test TESTOPTS="--seed=1"                 # what CI runs (MRI 3.3/3.4/4.0/head + JRuby, Linux + macOS)
ruby -Ilib -Itest test/sqlite3_test.rb -n test_binds      # one test
```

rb2go check (CI's second job), from a ruby2go checkout with this repo copied over `gems/sqlite3-fiddle`:

```sh
go run ./cmd/rb2go test ../sqlite3-fiddle/test/sqlite3_test.rb --seed 1
```

If the real `sqlite3` gem is installed, `-Ilib` must come first or it shadows this one.

## Architecture

Everything is `lib/sqlite3.rb`; tests are `test/sqlite3_test.rb`. The test file is shared with ruby2go's `testdata/test/` and is also run against the real gem, so tests must assert real-gem behavior, not this gem's quirks.

- `SQLite3::C` — `Fiddle::Importer` `extern` declarations. Add C functions here as literal signature strings; rb2go compiles those literals (decision 326), so don't build signatures dynamically. Optional symbols (e.g. `sqlite3_error_offset`, SQLite >= 3.38) are probed with `sym_defined?` and wrapped in a nilable `Fiddle::Function`.
- Library name: `libsqlite3.dylib` on darwin, `libsqlite3.so.0` elsewhere (`SQLite3.__lib_name`).
- `Database` is opened twice: once for pragma accessors (the gem's `Pragmas` module folded in so `self` is typed), once for the core API.
- Errors: result codes map to the `SQLite3::*Exception` subclasses via `SQLite3.__exception`; `Exception#sql_error` renders a caret at the error offset.
- `create_function` / `define_function`: `Fiddle::Closure::BlockCaller` kept alive in `@functions`. Ruby exceptions can't unwind through C, so the callback parks them in `@pending_error` and the step that invoked the function re-raises.

## Constraints from rb2go

The code is written for a static compiler, which explains the non-idiomatic bits:

- `# rbs_inline: enabled` with `#:` type annotations on methods and ivars — rb2go reads these. Keep them on new code and keep types precise (`untyped` only where the real gem is dynamic).
- `Blob` is a marker class, not a `String` subclass, so `[str, Blob.new(x)]` types as `Array[String | Blob]` (decision 150).
- Text columns get explicit `force_encoding(UTF_8)`; MRI's `Pointer.read` returns binary (decision 136).
- Blocks have fixed arity (no splats through typed blocks) — hence `create_function`'s six-arg cap.
- Methods prefixed `__` are internal helpers, not gem API.

Intentional differences from the real gem (keep README in sync if these change): `Blob` not a String; `prepare`/`query`/`execute` with a block return the Statement/ResultSet/`[]` rather than the block's value; no aggregates, authorizers, busy handlers, tracing, collations, extensions, backup, or serialize.

## Style

Repo uses `# ponytail: <what>` to mark deliberate shortcuts with an upgrade path.
