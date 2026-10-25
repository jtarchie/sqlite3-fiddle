# rbs_inline: enabled

# Times common sqlite3 workloads; prints one "name seconds" line each. Run as-is under MRI/JRuby, with -Ilib for this gem, or compiled by rugaroo.

require "sqlite3"

ROWS = 100_000

#: (String) { () -> void } -> void
def measure(name)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  puts format("%-16s %.3f", name, Process.clock_gettime(Process::CLOCK_MONOTONIC) - start)
end

db = SQLite3::Database.new(":memory:")
db.execute("create table t (id integer primary key, name text, score real)")

measure("insert") do
  db.transaction do
    stmt = db.prepare("insert into t (name, score) values (?, ?)")
    i = 0
    while i < ROWS
      stmt.execute("name-#{i}", i * 0.5)
      i += 1
    end
    stmt.close
  end
end

measure("select") do
  rows = db.execute("select id, name, score from t")
  raise "got #{rows.length} rows" unless rows.length == ROWS
end

measure("select_hash") do
  n = 0
  stmt = db.prepare("select id, name, score from t")
  stmt.execute.each_hash { |_| n += 1 }
  stmt.close
  raise "got #{n} rows" unless n == ROWS
end

measure("point_lookup") do
  stmt = db.prepare("select name from t where id = ?")
  i = 1
  while i <= 20_000
    stmt.execute(i).to_a
    i += 1
  end
  stmt.close
end

db.define_function("twice") { |x| x * 2 }
measure("ruby_function") do
  db.get_first_value("select sum(twice(id)) from t")
end

db.close
