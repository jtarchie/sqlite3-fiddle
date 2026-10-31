# sqlite3-fiddle

A drop-in replacement for the [sqlite3 gem](https://github.com/sparklemotion/sqlite3-ruby) (2.10.1) in pure
Ruby: the same `lib/` layout and Ruby code as the gem, with its C extension (`ext/sqlite3`) replaced by a
Fiddle port in `lib/sqlite3/native/` that calls the system `libsqlite3`. No compiler needed, so it runs on MRI,
on JRuby, and compiles under [rugaroo](https://github.com/jtarchie/rugaroo), which vendors it to answer
`require "sqlite3"` (rugaroo's docs/design.md decision 328).

```ruby
require "sqlite3"

db = SQLite3::Database.new(":memory:")
db.execute("create table t (id integer primary key, name text)")
db.execute("insert into t (name) values (?)", ["a"])
p db.execute("select * from t")   # [[1, "a"]]
```

| upstream                  | here                                                  |
| ------------------------- | ----------------------------------------------------- |
| `lib/sqlite3.rb`, `lib/sqlite3/*.rb` | same files, same code, with `#:` type annotations |
| `ext/sqlite3/sqlite3.c`   | `lib/sqlite3/native/sqlite3.rb` (+ `ffi.rb`, the extern table) |
| `ext/sqlite3/database.c`, `aggregator.c` | `lib/sqlite3/native/database.rb`       |
| `ext/sqlite3/statement.c` | `lib/sqlite3/native/statement.rb`                     |
| `ext/sqlite3/backup.c`    | `lib/sqlite3/native/backup.rb`                        |
| `ext/sqlite3/exception.c` | `lib/sqlite3/native/exception.rb`                     |
| `test/*.rb`               | same files (plus `test/sqlite3_test.rb`, shared with rugaroo) |

## Which libsqlite3

`libsqlite3.so.0` on Linux. On macOS, Homebrew's (`brew install sqlite`) when it is installed, else the
system's, which is built without `load_extension` and is older than the 3.54 that `Database#deserialize`
needs. `SQLITE3_FIDDLE_LIB=/path/to/libsqlite3` overrides both. Features the loaded library lacks are left
undefined, as the C extension's `#ifdef HAVE_*` leaves them: `enable_load_extension`, `deserialize`,
`Statement#database_name`.

If the real `sqlite3` gem is installed too, put this gem's `lib` first on the load path or it shadows this one.

## Tests

Every upstream test file runs here, against this gem and against the real gem:

```sh
bundle exec rake test TESTOPTS="--seed=1"      # lib/ (MRI or JRuby)
bundle exec rake test:gem TESTOPTS="--seed=1"  # the sqlite3 gem's C extension, same files (MRI)
```

On MRI with Homebrew's sqlite: 390 runs, 0 failures, 5 skips. The skips are upstream's own: URI filenames and
the `dbstat`/`sqlite_dbpage` tables are tested only when the gem bundles its own sqlite
(`SQLITE_PACKAGED_LIBRARIES`), since system builds vary. Forced on, URI and dbstat pass with Homebrew's build;
it has no `sqlite_dbpage`.

## Not supported

Attempted, and out of reach on that runtime:

**JRuby**
- `fork` safety: JRuby has no `fork`, so the discard tests skip (as they do for the real gem on any runtime without it).
- Two upstream tests skip on JRuby (`test_replacing_a_collation_releases_the_previous_comparator`,
  `test_aggregate_instances_are_released_after_each_query`): they count live objects right after `GC.start`,
  which the JVM does not promise to honor. Run the suite with `JRUBY_OPTS=-X+O` so `ObjectSpace.each_object` works.

**rugaroo** (only `test/sqlite3_test.rb` runs there; these are compiled out with a class-body
`defined?(::Binding)` guard, which rugaroo folds to false and MRI/JRuby to true)
- Aggregates: `create_aggregate`, `create_aggregate_handler` and `define_aggregator` build classes at run time
  (`Class.new`, `define_method`).
- `Database#authorizer { }` (block form): rugaroo cannot store a block it never calls; `authorizer =` a callable works.
- `load_extension`, `enable_load_extension` and the `extensions:` option.
- `strict: true`: `sqlite3_db_config` is variadic, and rugaroo's purego cannot make variadic C calls.
- Fork safety: `Process._fork` cannot be prepended, so a forked child keeps its connections.
- `define_function` registers every function as variadic (`-1`), since rugaroo has no `Proc#arity`.
- `SQLite3::Blob` is a marker class, not a `String` subclass: rugaroo widens a `String` subclass to `String` in a
  mixed literal (its decision 150), losing the type. Columns still read back as Strings.
- `ResultSet#each`/`#each_hash` without a block (an Enumerator) raise `NotImplementedError`.

## Benchmark

`bench/benchmark.rb`: 100,000-row insert in a transaction, a full `select`, the same as hashes, 20,000
primary-key lookups, and a Ruby scalar function over every row. Seconds, lower is better.

| runtime                               | insert | select | select_hash | point_lookup | ruby_function |
| ------------------------------------- | -----: | -----: | ----------: | -----------: | ------------: |
| MRI 4.0.7, sqlite3 gem 2.10.1 (C ext) |   0.16 |   0.05 |        0.10 |         0.03 |          0.01 |
| MRI 4.0.7 `--yjit`, sqlite3 gem C ext |   0.12 |   0.05 |        0.09 |         0.02 |          0.01 |
| MRI 4.0.7, this gem                   |   1.03 |   1.36 |        1.37 |         0.33 |          0.50 |
| MRI 4.0.7 `--yjit`, this gem          |   0.83 |   1.27 |        1.24 |         0.27 |          0.43 |
| JRuby 10.1.2 (Java 27), this gem      |   2.09 |   1.19 |        0.97 |         0.29 |          0.53 |
| rugaroo (compiled to Go), this gem    |   0.15 |   0.21 |        0.26 |         0.05 |          0.10 |
| rugaroo `-cgo`, this gem              |   0.15 |   0.20 |        0.25 |         0.05 |          0.10 |

Best of three runs on an Apple M4, Homebrew sqlite 3.54.0 (the C ext gem bundles 3.54.1). Reproduce with
`ruby -Ilib bench/benchmark.rb`, `jruby -Ilib bench/benchmark.rb`, `ruby -e 'gem "sqlite3"' -e 'load "bench/benchmark.rb"'`,
and `rugaroo build -o bench bench/benchmark.rb && ./bench` (add `-cgo` for cgo instead of purego, rugaroo's decision 426).
On Linux, where purego reads errno with a second C call under a thread lock, `-cgo` is 15–26% faster on every row
(arm64: 0.196 → 0.167, 0.280 → 0.226, 0.379 → 0.285, 0.076 → 0.056, 0.146 → 0.108); on macOS the two are even.

Each row of `select` crosses Fiddle about ten times (step, column count, type and value per column), as the C
extension crosses into libsqlite3, and `ruby_function` crosses back into Ruby once per row plus three calls out.
Under rugaroo each crossing is a Go-to-C call (~46 ns, where the C extension pays a few ns): the same `select` made
straight from Go, with no Ruby at all, takes 0.08 s, so select, select_hash and ruby_function stay several times
slower than the C extension, while insert and point_lookup are close to it. rugaroo's docs/design.md decision 329
has how the compiled calls got there (from 1.14 / 1.67 / 2.16 / 0.48 / 0.56 s). Fiddle calls keep the GVL, as the C
extension does; fiddle's default hands it off and back on every call, which made MRI's reads ~5× slower.

## License

MIT (`LICENSE`). The Ruby code and tests ported from the sqlite3 gem keep its BSD-3-Clause license
(`LICENSE-sqlite3-ruby`).
