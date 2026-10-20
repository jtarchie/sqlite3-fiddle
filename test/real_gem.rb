# Loaded with -r by `rake test:gem`: the same test files then run against the sqlite3 gem's C extension instead of this repo's lib/.

lib = File.expand_path("../lib", __dir__)
$LOAD_PATH.reject! { |path| File.expand_path(path) == lib } # bundler puts this gem's lib on the path through the gemspec
gem "sqlite3", ENV.fetch("SQLITE3_GEM_VERSION", "2.10.1")
require "sqlite3"
abort "test:gem loaded #{$LOADED_FEATURES.grep(%r{/sqlite3\.rb\z}).first}, not the sqlite3 gem" unless SQLite3::Database.instance_method(:close).source_location.nil?
