# frozen_string_literal: true

require_relative "test_helper"

class ZlibFormatTest < Minitest::Test
  def test_both_directions
    sample_inputs.each do |name, data|
      [0, 1, 6].each do |level|
        assert_equal data, Zlib::Inflate.inflate(Rdeflate.zlib_compress(data, level: level)), "#{name} @#{level}"
        assert_equal data, Rdeflate.zlib_decompress(Zlib::Deflate.deflate(data, level)), "#{name} @#{level}"
      end
    end
  end

  def test_header_matches_zlib_conventions
    { 0 => "\x78\x01", 1 => "\x78\x01", 2 => "\x78\x5E", 6 => "\x78\x9C", 9 => "\x78\xDA" }.each do |level, header|
      assert_equal header.b, Rdeflate.zlib_compress("x", level: level).byteslice(0, 2), "level #{level}"
      assert_equal header.b, Zlib::Deflate.deflate("x", level).byteslice(0, 2), "zlib level #{level}"
    end
  end

  def test_large_round_trip
    data = random_text(1_100_000, seed: 12)
    assert_equal data, Zlib::Inflate.inflate(Rdeflate.zlib_compress(data))
    assert_equal data, Rdeflate.zlib_decompress(Zlib::Deflate.deflate(data))
  end

  def test_corrupt_streams
    good = Rdeflate.zlib_compress("hello world" * 100)
    bad_check = good.dup.tap { |s| s.setbyte(1, s.getbyte(1) ^ 1) }
    bad_method = "\x79\x9C".b + good.byteslice(2..)
    bad_adler = good.dup.tap { |s| s.setbyte(-1, s.getbyte(-1) ^ 0xFF) }
    assert_raises(Rdeflate::DataError) { Rdeflate.zlib_decompress(bad_check) }
    assert_raises(Rdeflate::DataError) { Rdeflate.zlib_decompress(bad_method) }
    assert_raises(Rdeflate::ChecksumError) { Rdeflate.zlib_decompress(bad_adler) }
    assert_raises(Rdeflate::TruncatedError) { Rdeflate.zlib_decompress(good.byteslice(0, good.bytesize - 2)) }
    assert_raises(Rdeflate::TruncatedError) { Rdeflate.zlib_decompress("\x78".b) }
    assert_raises(Rdeflate::DataError) { Rdeflate.zlib_decompress(good + "junk") }
  end

  def test_preset_dictionary_is_reported
    z = Zlib::Deflate.new
    z.set_dictionary("hello")
    stream = z.deflate("hello hello", Zlib::FINISH)
    err = assert_raises(Rdeflate::Error) { Rdeflate.zlib_decompress(stream) }
    assert_match(/dictionar/, err.message)
  end

  def test_every_payload_bit_flip_is_detected
    data = random_text(3000)
    good = Rdeflate.zlib_compress(data)
    (2...good.bytesize).step(7) do |i|
      bad = good.dup
      bad.setbyte(i, bad.getbyte(i) ^ (1 << (i % 8)))
      assert_raises(Rdeflate::DataError, "flip at #{i}") { Rdeflate.zlib_decompress(bad) }
    end
  end
end
