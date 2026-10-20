# frozen_string_literal: true

require_relative "test_helper"

class ApiTest < Minitest::Test
  def test_compress_and_auto_detect
    data = random_text(20_000)
    Rdeflate::FORMATS.each do |format|
      packed = Rdeflate.compress(data, format: format, level: 7)
      assert_equal format, Rdeflate.detect_format(packed)
      assert_equal data, Rdeflate.decompress(packed)
      assert_equal data, Rdeflate.decompress(packed, format: format)
    end
  end

  def test_decompress_detects_foreign_streams
    data = "detect me " * 100
    assert_equal data, Rdeflate.decompress(Zlib.gzip(data))
    assert_equal data, Rdeflate.decompress(Zlib::Deflate.deflate(data))
    assert_equal data, Rdeflate.decompress(zlib_raw_deflate(data))
  end

  def test_unknown_format
    assert_raises(ArgumentError) { Rdeflate.compress("x", format: :bzip2) }
    assert_raises(ArgumentError) { Rdeflate.decompress("x", format: :lzma) }
  end

  def test_error_hierarchy
    assert_operator Rdeflate::ChecksumError, :<, Rdeflate::DataError
    assert_operator Rdeflate::TruncatedError, :<, Rdeflate::DataError
    assert_operator Rdeflate::DataError, :<, Rdeflate::Error
  end
end
