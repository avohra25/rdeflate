# frozen_string_literal: true

require_relative "test_helper"
require "rdeflate/cli"
require "tmpdir"

class CLITest < Minitest::Test
  def run_cli(*args, stdin: "")
    out = StringIO.new("".b)
    err = StringIO.new
    status = Rdeflate::CLI.new(args, stdin: StringIO.new(stdin.b), stdout: out, stderr: err).run
    [status, out.string, err.string]
  end

  def test_compress_and_decompress_files
    Dir.mktmpdir do |dir|
      src = File.join(dir, "words.txt")
      data = random_text(50_000)
      File.binwrite(src, data)
      status, = run_cli("compress", "-9", src)
      assert_equal 0, status
      reader = Zlib::GzipReader.open("#{src}.gz")
      assert_equal data, reader.read.b
      assert_equal "words.txt", reader.orig_name
      reader.close
      File.delete(src)
      assert_equal 0, run_cli("decompress", "#{src}.gz").first
      assert_equal data, File.binread(src)
    end
  end

  def test_stdin_to_stdout_in_every_format
    data = "pipe me " * 500
    %w[--gzip --zlib --raw].each do |flag|
      status, packed, = run_cli("c", flag, stdin: data)
      assert_equal 0, status
      _, unpacked, = run_cli("d", stdin: packed) # auto-detect
      assert_equal data, unpacked, flag
    end
    _, raw, = run_cli("c", "--format", "raw", "-1", stdin: data)
    assert_equal data, zlib_raw_inflate(raw)
  end

  def test_output_option_and_refusing_to_overwrite
    Dir.mktmpdir do |dir|
      src = File.join(dir, "a")
      out = File.join(dir, "a.zz")
      File.write(src, "abc" * 100)
      assert_equal 0, run_cli("c", "--zlib", src, "-o", out).first
      assert_equal "abc" * 100, Zlib::Inflate.inflate(File.binread(out))
      status, _, err = run_cli("c", "--zlib", src, "-o", out)
      assert_equal 1, status
      assert_match(/already exists/, err)
      assert_equal 0, run_cli("c", "--zlib", "-f", src, "-o", out).first
    end
  end

  def test_info_lists_members
    Dir.mktmpdir do |dir|
      path = File.join(dir, "multi.gz")
      File.binwrite(path, Rdeflate.gzip("one", filename: "one.txt", mtime: 86_400) + Rdeflate.gzip("two"))
      status, out, = run_cli("info", path)
      assert_equal 0, status
      assert_match(/gzip/, out)
      assert_match(/member 1: .*name="one.txt" mtime=1970-01-02T00:00:00Z/, out)
      assert_match(/member 2: /, out)
    end
  end

  def test_errors_and_usage
    status, _, err = run_cli("d", stdin: Rdeflate.gzip("x").byteslice(0, 12))
    assert_equal 1, status
    assert_match(/rdeflate: .*end of/, err)
    assert_equal 2, run_cli.first
    assert_equal 2, run_cli("c", "--level", "12").first
    assert_equal 2, run_cli("c", "--bogus").first
    status, out, = run_cli("c", "--version")
    assert_equal [0, "rdeflate #{Rdeflate::VERSION}\n"], [status, out]
  end

  def test_verbose_reports_ratio
    _, _, err = run_cli("c", "-v", stdin: "a" * 10_000)
    assert_match(/stdin: 10000 -> \d+ bytes \(\d+\.\d% saved\)/, err)
  end

  def test_bin_script_runs
    bin = File.expand_path("../bin/rdeflate", __dir__)
    packed = IO.popen([RbConfig.ruby, bin, "compress", "--zlib"], "r+b") do |io|
      io.write("through the real executable")
      io.close_write
      io.read
    end
    assert_equal "through the real executable", Zlib::Inflate.inflate(packed)
  end
end
