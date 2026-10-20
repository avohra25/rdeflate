# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = true
end

desc "Compare rdeflate with Zlib on a few corpora (prints a Markdown table)"
task :bench do
  ruby "-Ilib", "benchmarks/bench.rb"
end

task default: :test
