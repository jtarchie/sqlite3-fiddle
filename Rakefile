# frozen_string_literal: true

require "rake/testtask"

TESTS = FileList["test/test_*.rb", "test/sqlite3_test.rb"]

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.test_files = TESTS
end

namespace :test do
  Rake::TestTask.new(:gem) do |t|
    t.description = "Run the same tests against the sqlite3 gem (its C extension), not lib/"
    t.libs = ["test"]
    t.ruby_opts << "-r#{File.expand_path("test/real_gem", __dir__)}"
    t.test_files = TESTS
  end
end

task default: :test
