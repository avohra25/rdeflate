# frozen_string_literal: true

# Compares rdeflate with Ruby's Zlib binding (C zlib) on 1 MiB corpora.
#
#   ruby -Ilib benchmarks/bench.rb [levels]      # default levels: 1,6,9
#
# Prints a Markdown table: compressed size as % of input, and throughput in
# MB/s (input bytes per second) for compression and decompression.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rdeflate"
require "zlib"
require "rbconfig"

SIZE = 1 << 20

def ruby_source
  files = Dir[File.join(RbConfig::CONFIG["rubylibdir"], "**/*.rb")].sort
  out = +""
  files.each do |f|
    out << File.binread(f)
    break if out.bytesize >= SIZE
  end
  out.byteslice(0, SIZE)
end

def shared_library
  dirs = RbConfig::CONFIG.values_at("libdir", "archlibdir").compact
  path = dirs.map { |d| File.join(d, RbConfig::CONFIG["LIBRUBY_SO"].to_s) }.find { |f| File.file?(f) }
  path ||= RbConfig.ruby
  data = File.binread(path)
  data = data * ((SIZE / data.bytesize) + 1) if data.bytesize < SIZE
  data.byteslice(0, SIZE)
end

def access_log
  rng = Random.new(1)
  paths = %w[/ /login /api/items /api/items/42 /static/app.js /static/app.css /favicon.ico /search]
  out = +""
  while out.bytesize < SIZE
    ip = Array.new(4) { rng.rand(256) }.join(".")
    out << format(%(%s - - [20/Oct/2026:%02d:%02d:%02d -0700] "GET %s HTTP/1.1" %d %d\n),
                  ip, rng.rand(24), rng.rand(60), rng.rand(60), paths.sample(random: rng),
                  [200, 200, 200, 304, 404].sample(random: rng), rng.rand(100_000))
  end
  out.byteslice(0, SIZE)
end

CORPORA = {
  "Ruby source" => ruby_source,
  "libruby.so" => shared_library,
  "access log" => access_log,
  "random" => Random.new(2).bytes(SIZE)
}.freeze

def best_time(runs)
  Array.new(runs) do
    t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
  end.min
end

def zlib_deflate(data, level)
  z = Zlib::Deflate.new(level, -Zlib::MAX_WBITS)
  out = z.deflate(data, Zlib::FINISH)
  z.close
  out
end

def zlib_inflate(data)
  z = Zlib::Inflate.new(-Zlib::MAX_WBITS)
  out = z.inflate(data)
  z.close
  out
end

levels = (ARGV.first || "1,6,9").split(",").map(&:to_i)
mbps = ->(seconds) { format("%.2f", SIZE / seconds / 1e6) }
pct = ->(bytes) { format("%.2f%%", 100.0 * bytes / SIZE) }

puts "ruby #{RUBY_VERSION} (#{RUBY_PLATFORM}), zlib #{Zlib.zlib_version}, input #{SIZE} bytes per corpus"
puts
puts "| Corpus | Level | rdeflate size | zlib size | rdeflate compress | zlib compress | rdeflate inflate | zlib inflate |"
puts "|---|---:|---:|---:|---:|---:|---:|---:|"
CORPORA.each do |name, data|
  levels.each do |level|
    ours = Rdeflate.deflate(data, level: level)
    theirs = zlib_deflate(data, level)
    raise "round trip failed for #{name}" unless zlib_inflate(ours) == data && Rdeflate.inflate(theirs) == data

    t_ours = best_time(2) { Rdeflate.deflate(data, level: level) }
    t_zlib = best_time(5) { zlib_deflate(data, level) }
    i_ours = best_time(3) { Rdeflate.inflate(ours) }
    i_zlib = best_time(5) { zlib_inflate(theirs) }
    puts "| #{name} | #{level} | #{pct[ours.bytesize]} | #{pct[theirs.bytesize]} | " \
         "#{mbps[t_ours]} MB/s | #{mbps[t_zlib]} MB/s | #{mbps[i_ours]} MB/s | #{mbps[i_zlib]} MB/s |"
    $stdout.flush
  end
end
