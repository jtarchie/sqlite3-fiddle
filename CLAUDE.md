# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A drop-in replacement for the sqlite3 gem (2.10.1) in pure Ruby: upstream's `lib/` files and tests, with its C extension replaced by a Fiddle port over the system `libsqlite3`. Three consumers that must all work:

- **MRI** (Ruby >= 3.3) and **JRuby** (10+, via fiddle's FFI backend) — plain gem; every upstream test passes.
- **rb2go** ([jtarchie/ruby2go](https://github.com/jtarchie/ruby2go), locally `../transpiler`) — a Ruby→Go compiler that vendors this repo (`gems/sqlite3-fiddle` submodule, mirrored into `vendored/sqlite3-fiddle` by `scripts/vendor-gems`) and answers `require "sqlite3"` with it. Only `test/sqlite3_test.rb` runs there; the compiled program's output must match MRI's.

"decision N" comments refer to ruby2go's `docs/design.md`, not anything in this repo.

## Commands

```sh
bundle exec rake test TESTOPTS="--seed=1"       # all tests against lib/ (CI: MRI 3.3/3.4/4.0/head + JRuby, Linux + macOS)
bundle exec rake test:gem TESTOPTS="--seed=1"   # the same files against the real sqlite3 gem (test/real_gem.rb drops lib/ from the path)
ruby -Ilib -Itest test/test_database.rb -n test_strict_mode   # one test
JRUBY_OPTS=-X+O jruby -Ilib -Itest test/test_collation.rb     # JRuby needs ObjectSpace for some upstream tests
ruby -Ilib bench/benchmark.rb                    # README's benchmark table
```

rb2go check (CI's second job), from a ruby2go checkout with this repo's `lib/` copied into `vendored/sqlite3-fiddle`:

```sh
go run ./cmd/rb2go test ../sqlite3-fiddle/test/sqlite3_test.rb --seed 1
```

If the real `sqlite3` gem is installed, `-Ilib` must come first or it shadows this one.

## Architecture

`lib/sqlite3.rb` and `lib/sqlite3/*.rb` are upstream's Ruby files with `#:` annotations; keep them as close to upstream as rb2go allows. `lib/sqlite3/native/*.rb` stands in for `ext/sqlite3/*.c`, one file per C file, defining the same (public and private) methods the C extension does. `test/test_*.rb` and `test/helper.rb` are upstream's tests, unmodified except two JRuby GC skips; `test/sqlite3_test.rb` is shared with ruby2go's `testdata/test/` (keep both copies identical) and also runs against the real gem, so tests assert real-gem behavior.

- `SQLite3::C` (`native/ffi.rb`) — `Fiddle::Importer` `extern` declarations as literal signature strings; rb2go compiles those literals (decision 326), so don't build signatures dynamically. `import_function` is overridden to pass `need_gvl: true` (fiddle's default hands off the GVL per call, ~5× slower). Optional symbols: either a nilable `Fiddle::Function` (used inside always-defined methods: `ERROR_OFFSET`, `DB_NAME`, `DB_CONFIG`) or an extern declared from file-level code under `rescue Fiddle::DLError`, whose methods are defined behind a class-body `if C.respond_to?(:sqlite3_x)` (true on MRI when present; folds to false in rb2go), mirroring the C ext's `#ifdef HAVE_*`.
- Library: Homebrew's `libsqlite3.dylib` on darwin when present, else the system's; `libsqlite3.so.0` elsewhere; `SQLITE3_FIDDLE_LIB` overrides.
- Callbacks (functions, aggregates, collations, busy/trace/authorizer/progress) are `Fiddle::Closure::BlockCaller`s kept by `Database#__keep` (slotted ones are released on replacement). Each is also wrapped in `Fiddle::Pointer.to_ptr(closure)`: fiddle hands libffi the closure's VALUE unpinned, so GC compaction would move it out from under sqlite; the Pointer's `rb_gc_mark` pins it.
- Ruby exceptions can't unwind through C: callbacks park them with `__park` and `step`/`prepare`/`exec_batch` re-raise via `__raise_pending` (the C ext's `rb_errinfo` dance).
- String encodings follow the C ext exactly: `rb_str_new2` sites are binary (`C.cstr`), `rb_utf8_str_new_cstr` sites UTF-8 (`C.ustr`).

## Constraints from rb2go

- `# rbs_inline: enabled` with `#:` type annotations on methods and ivars (first assignment, inline). Keep types precise (`untyped` only where the real gem is dynamic).
- **MRI-only code** goes behind a class-body `if defined?(::Binding)` (rb2go has no `Binding`, so it folds to the `else` arm; MRI/JRuby take the `then` arm). Used for: aggregates, `authorizer { }`, extension loading, the fork hook, `Proc#arity`, `enum_for`, the variadic `sqlite3_db_config`, and `Blob < String` (rb2go gets a marker class, decision 150). Each fenced feature is listed under README "Not supported"; keep that list in sync.
- A method whose block form returns the block's value (`prepare`, `query`, `execute`, `execute2`, `table_info`) has a required-block signature returning `untyped`, plus a typed `__name_<argc>` method that rb2go routes block-less calls to (its decision 12 overload convention). The MRI body calls the same helper when `block_given?` is false.
- No non-local `return` from blocks, no `Proc#arity`, no Bignum literals (`bit_length` for int64 range checks), no `&block` forwarding where the callee requires a block (rb2go reads a nil `&block` as given). A `String` subclass doesn't match `when String`: give `Blob` its own `when` arm first.
- Pragma accessors live on `Database` (in `pragmas.rb`); `module Pragmas` keeps only the mode tables. rb2go can't type `self` inside an included module.
- Methods prefixed `__` are internal helpers, not gem API.

Fiddle differs across MRI's C ext, JRuby's FFI backend, and rb2go's prelude (`prelude/fiddle.rb`). Stick to the intersection: free scratch memory with `Pointer.malloc(n, Fiddle::RUBY_FREE)` + `call_free`; test `sym_defined?` for truthiness; detect the OS via `RbConfig::CONFIG["host_os"]`; on JRuby a variadic call's fixed `voidp` args must be `Fiddle::Pointer`s, not Integers. CI's JRuby job needs Java 21.

## Style

Comments are single-line and say why; put one on the `def` line rather than above a `#:` annotation. Repo uses `# ponytail: <what>` to mark deliberate shortcuts with an upgrade path.
