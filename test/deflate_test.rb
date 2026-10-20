# frozen_string_literal: true

require_relative "test_helper"

class DeflateTest < Minitest::Test
  def test_zlib_inflates_our_output
    sample_inputs.each do |name, data|
      [0, 1, 6, 9].each do |level|
        out = Rdeflate.deflate(data, level: level)
        assert_equal data, zlib_raw_inflate(out), "#{name} level #{level}"
        assert_equal data, Rdeflate.inflate(out), "#{name} level #{level} (self)"
      end
    end
  end

  def test_level_zero_is_stored
    d = Rdeflate::Deflater.new(level: 0)
    out = d.deflate("hello" * 30_000) + d.finish
    assert_equal({ stored: 3 }, d.stats)
    assert_equal ("hello" * 30_000), zlib_raw_inflate(out)
  end

  def test_block_type_selection
    stats = lambda do |data|
      d = Rdeflate::Deflater.new(level: 6)
      d.deflate(data)
      d.finish
      d.stats
    end
    assert_equal [:fixed], stats.call("hi").keys, "tiny input -> fixed"
    assert_equal [:stored], stats.call(Random.new(1).bytes(50_000)).keys, "random -> stored"
    assert_includes stats.call(random_text(100_000)).keys, :dynamic, "text -> dynamic"
  end

  def test_empty_input
    out = Rdeflate.deflate("")
    assert_equal "\x03\x00".b, out
    assert_equal "", zlib_raw_inflate(out)
  end

  def test_rejects_bad_levels
    [-1, 10, 6.0, "6", nil].each do |level|
      assert_raises(ArgumentError) { Rdeflate::Deflater.new(level: level) }
    end
  end

  def test_finish_twice_raises
    d = Rdeflate::Deflater.new
    d.finish
    assert_raises(Rdeflate::Error) { d.finish }
    assert_raises(Rdeflate::Error) { d.deflate("x") }
  end

  def test_output_is_binary_for_non_binary_input
    out = Rdeflate.deflate("ünïcödé " * 50)
    assert_equal Encoding::BINARY, out.encoding
    assert_equal ("ünïcödé " * 50).b, zlib_raw_inflate(out)
  end
end
