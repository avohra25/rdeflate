# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class StreamTest < Minitest::Test
  # Records each write so we can check output is produced incrementally.
  class RecordingIO
    attr_reader :writes

    def initialize
      @writes = []
    end

    def write(str)
      @writes << str.dup
      str.bytesize
    end

    def string
      @writes.join.b
    end
  end

  def test_writer_streams_blocks
    io = RecordingIO.new
    gz = Rdeflate::GzipWriter.new(io, filename: "log.txt")
    text = random_text(400_000)
    text.bytes.each_slice(8192) { |chunk| gz << chunk.pack("C*") }
    gz.finish
    assert_operator io.writes.size, :>, 5, "compressed data should be written before finish"
    reader = Zlib::GzipReader.new(StringIO.new(io.string))
    assert_equal text, reader.read.b
    assert_equal "log.txt", reader.orig_name
  end

  def test_writer_print_helpers
    io = StringIO.new
    gz = Rdeflate::GzipWriter.new(io)
    gz.puts "one", %w[two three]
    gz.print "four", 5
    gz.write("\n", "six\n")
    gz.puts
    gz.finish
    assert_equal "one\ntwo\nthree\nfour5\nsix\n\n", Zlib.gunzip(io.string)
    assert_raises(IOError) { gz.write("more") }
  end

  def test_open_with_block_and_reader
    Dir.mktmpdir do |dir|
      path = File.join(dir, "t.gz")
      Rdeflate::GzipWriter.open(path, level: 9, mtime: 1_600_000_000) { |gz| gz.write("line 1\nline 2\n") }
      assert_equal "line 1\nline 2\n", Zlib::GzipReader.open(path, &:read)
      Rdeflate::GzipReader.open(path) do |r|
        assert_equal ["line 1\n", "line 2\n"], r.each_line.to_a
        assert_equal Time.at(1_600_000_000), r.mtime
      end
      File.open(path, "rb") { |f| assert_equal "line 1\nline 2\n", Rdeflate::GzipReader.new(f).read }
    end
  end
end
