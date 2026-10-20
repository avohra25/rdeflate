# frozen_string_literal: true

require_relative "test_helper"

# Round trips in both directions against Ruby's bundled zlib.
class CrossCheckTest < Minitest::Test
  def test_every_level_both_directions
    sample_inputs(seed: 77).each do |name, data|
      (0..9).each do |level|
        ours = Rdeflate.deflate(data, level: level)
        assert_equal data, zlib_raw_inflate(ours), "zlib inflating ours: #{name} @#{level}"
        assert_equal data, Rdeflate.inflate(zlib_raw_deflate(data, level)), "ours inflating zlib: #{name} @#{level}"
      end
    end
  end

  def test_random_lengths_and_alphabets
    rng = Random.new(31)
    150.times do |i|
      alphabet = rng.rand(1..256)
      data = Array.new(rng.rand(0..3000)) { rng.rand(alphabet) }.pack("C*")
      data *= rng.rand(1..4) if i.even?
      level = rng.rand(0..9)
      assert_equal data, zlib_raw_inflate(Rdeflate.deflate(data, level: level)), "case #{i}"
    end
  end

  def test_large_inputs
    text = random_text(1_200_000, seed: 41)
    random = Random.new(42).bytes(1_100_000)
    [[text, 6], [text, 1], [random, 6]].each do |data, level|
      ours = Rdeflate.deflate(data, level: level)
      assert_equal data, zlib_raw_inflate(ours)
      assert_equal data, Rdeflate.inflate(zlib_raw_deflate(data, level))
    end
  end

  def test_ratio_is_close_to_zlib
    data = random_text(400_000, seed: 8)
    [1, 6, 9].each do |level|
      ours = Rdeflate.deflate(data, level: level).bytesize
      theirs = zlib_raw_deflate(data, level).bytesize
      assert_operator ours, :<=, (theirs * 1.03).ceil, "level #{level}: #{ours} vs zlib #{theirs}"
    end
  end

  def test_streaming_chunks_round_trip
    data = random_text(300_000, seed: 9)
    rng = Random.new(4)
    d = Rdeflate::Deflater.new(level: 6)
    out = +""
    pos = 0
    while pos < data.bytesize
      n = rng.rand(1..20_000)
      out << d.deflate(data.byteslice(pos, n))
      pos += n
    end
    out << d.finish
    assert_equal data, zlib_raw_inflate(out)
  end
end
