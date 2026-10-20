# frozen_string_literal: true

require_relative "test_helper"

class GzipFormatTest < Minitest::Test
  def zlib_gzip(data, level: 6, name: nil, mtime: nil, comment: nil)
    io = StringIO.new("".b)
    gz = Zlib::GzipWriter.new(io, level)
    gz.orig_name = name if name
    gz.mtime = mtime if mtime
    gz.comment = comment if comment
    gz.write(data)
    gz.finish
    io.string
  end

  def zlib_gunzip(data)
    Zlib::GzipReader.new(StringIO.new(data)).read.b
  end

  def test_both_directions
    sample_inputs.each do |name, data|
      [1, 6].each do |level|
        assert_equal data, zlib_gunzip(Rdeflate.gzip(data, level: level)), "#{name} @#{level}"
        assert_equal data, Rdeflate.gunzip(zlib_gzip(data, level: level)), "#{name} @#{level}"
      end
    end
  end

  def test_header_fields_are_written
    gz = Rdeflate.gzip("data", filename: "notes.txt", comment: "a comment", mtime: Time.at(1_700_000_000))
    reader = Zlib::GzipReader.new(StringIO.new(gz))
    assert_equal "data", reader.read
    assert_equal "notes.txt", reader.orig_name
    assert_equal "a comment", reader.comment
    assert_equal 1_700_000_000, reader.mtime.to_i
    assert_equal Zlib::OS_UNIX, reader.os_code
  end

  def test_header_fields_are_read
    m = Rdeflate::GzipFormat.members(zlib_gzip("abc", name: "x.bin", mtime: 123, comment: "hi")).first
    assert_equal "abc", m.data
    assert_equal "x.bin", m.filename
    assert_equal "hi", m.comment
    assert_equal 123, m.mtime
  end

  def test_extra_field_header_crc_and_latin1_names
    gz = Rdeflate.gzip("payload", filename: "café.txt", extra: "AB\x03\x00xyz".b, header_crc: true, text: true)
    m = Rdeflate::GzipFormat.members(gz).first
    assert_equal "payload", m.data
    assert_equal "café.txt", m.filename
    assert_equal "AB\x03\x00xyz".b, m.extra
    assert m.text
    bad = gz.dup
    bad.setbyte(12, bad.getbyte(12) ^ 1) # inside the extra field, covered by FHCRC
    assert_raises(Rdeflate::ChecksumError) { Rdeflate.gunzip(bad) }
  end

  def test_multi_member
    a = Rdeflate.gzip("first ", filename: "a")
    b = zlib_gzip("second ", name: "b")
    c = Rdeflate.gzip("", level: 0)
    d = Rdeflate.gzip("third")
    all = a + b + c + d
    assert_equal "first second third", Rdeflate.gunzip(all)
    assert_equal %w[a b] + [nil, nil], Rdeflate::GzipFormat.members(all).map(&:filename)
    assert_equal "first second third", Zlib::GzipReader.zcat(StringIO.new(all))
  end

  def test_trailing_zero_padding_ok_but_garbage_rejected
    gz = Rdeflate.gzip("hello")
    assert_equal "hello", Rdeflate.gunzip(gz + ("\0" * 512))
    assert_raises(Rdeflate::DataError) { Rdeflate.gunzip(gz + "garbage") }
  end

  def test_corruption_is_detected
    gz = Rdeflate.gzip(random_text(5000))
    assert_raises(Rdeflate::DataError) { Rdeflate.gunzip("\x1F\x8C".b + gz.byteslice(2..)) }
    assert_raises(Rdeflate::TruncatedError) { Rdeflate.gunzip(gz.byteslice(0, 5)) }
    assert_raises(Rdeflate::TruncatedError) { Rdeflate.gunzip(gz.byteslice(0, gz.bytesize - 3)) }
    bad_crc = gz.dup.tap { |s| s.setbyte(-6, s.getbyte(-6) ^ 0x40) }
    assert_raises(Rdeflate::ChecksumError) { Rdeflate.gunzip(bad_crc) }
    bad_len = gz.dup.tap { |s| s.setbyte(-1, 1) }
    assert_raises(Rdeflate::ChecksumError) { Rdeflate.gunzip(bad_len) }
    bad_method = gz.dup.tap { |s| s.setbyte(2, 7) }
    assert_raises(Rdeflate::DataError) { Rdeflate.gunzip(bad_method) }
    bad_flags = gz.dup.tap { |s| s.setbyte(3, 0x80) }
    assert_raises(Rdeflate::DataError) { Rdeflate.gunzip(bad_flags) }
  end

  def test_rejects_nul_in_filename
    assert_raises(ArgumentError) { Rdeflate.gzip("x", filename: "a\0b") }
  end

  def test_large_round_trip
    data = Random.new(77).bytes(300_000) + random_text(900_000)
    assert_equal data, zlib_gunzip(Rdeflate.gzip(data))
    assert_equal data, Rdeflate.gunzip(zlib_gzip(data))
  end
end
