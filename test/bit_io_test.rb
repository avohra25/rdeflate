# frozen_string_literal: true

require_relative "test_helper"

class BitIOTest < Minitest::Test
  def test_reads_lsb_first
    r = Rdeflate::BitReader.new("\xB4\x01".b) # 1011_0100 0000_0001
    assert_equal 0, r.bits(1)
    assert_equal 0b10, r.bits(2)
    assert_equal 0b10110, r.bits(5)
    assert_equal 1, r.bits(8)
  end

  def test_writer_reader_roundtrip
    rng = Random.new(3)
    fields = Array.new(2000) do
      n = rng.rand(0..24)
      [rng.rand(1 << n), n]
    end
    data = bits(*fields)
    r = Rdeflate::BitReader.new(data)
    fields.each { |value, n| assert_equal value, r.bits(n) }
  end

  def test_align_and_read_bytes
    w = Rdeflate::BitWriter.new
    w.write_bits(0b101, 3).align.write_bytes("hi").write_bits(1, 1).align
    assert_equal "\x05hi\x01".b, w.string
    r = Rdeflate::BitReader.new(w.string)
    assert_equal 0b101, r.bits(3)
    r.align
    assert_equal "hi", r.read_bytes(2)
    assert_equal 3, r.pos
  end

  def test_align_returns_buffered_bytes
    r = Rdeflate::BitReader.new("\xFF\xAA\xBB\xCC".b)
    r.bits(3)
    r.decode(Rdeflate::Huffman::FIXED_LITLEN) # pulls more bytes into the buffer
    r.align
    assert_equal 2, r.pos
    assert_equal "\xBB\xCC".b, r.read_bytes(2)
  end

  def test_truncation
    r = Rdeflate::BitReader.new("\x01".b)
    r.bits(8)
    assert_raises(Rdeflate::TruncatedError) { r.bits(1) }
    r2 = Rdeflate::BitReader.new("ab")
    assert_raises(Rdeflate::TruncatedError) { r2.read_bytes(3) }
  end

  def test_write_bytes_requires_alignment
    w = Rdeflate::BitWriter.new.write_bits(1, 1)
    assert_raises(ArgumentError) { w.write_bytes("x") }
  end

  def test_take_drains_complete_bytes
    w = Rdeflate::BitWriter.new
    w.write_bits(0xABC, 12)
    assert_equal "\xBC".b, w.take
    assert_equal 4, w.pending_bits
    w.align
    assert_equal "\x0A".b, w.take
  end
end
