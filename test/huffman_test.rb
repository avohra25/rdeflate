# frozen_string_literal: true

require_relative "test_helper"

class HuffmanTest < Minitest::Test
  H = Rdeflate::Huffman

  def test_canonical_codes_rfc_example
    # RFC 1951 3.2.2: lengths (3,3,3,3,3,2,4,4) for A..H.
    codes = H.canonical_codes([3, 3, 3, 3, 3, 2, 4, 4])
    assert_equal [0b010, 0b011, 0b100, 0b101, 0b110, 0b00, 0b1110, 0b1111], codes
  end

  def test_reverse
    assert_equal 0b0011, H.reverse(0b1100, 4)
    assert_equal 0b1, H.reverse(0b1, 1)
    assert_equal 0b100000000000000, H.reverse(1, 15)
  end

  def test_decoder_decodes_every_symbol
    lengths = [3, 3, 3, 3, 3, 2, 4, 4]
    dec = H::Decoder.new(lengths)
    codes = H.canonical_codes(lengths)
    fields = lengths.each_index.map { |s| [H.reverse(codes[s], lengths[s]), lengths[s]] }
    r = Rdeflate::BitReader.new(bits(*fields))
    lengths.each_index { |s| assert_equal s, r.decode(dec) }
  end

  def test_rejects_oversubscribed
    assert_raises(Rdeflate::DataError) { H::Decoder.new([1, 1, 1]) }
  end

  def test_incomplete_rules
    H::Decoder.new([0, 1, 0]) # single length-1 code: allowed (zlib does too)
    H::Decoder.new([0, 0, 0]) # empty: allowed, but nothing decodes
    assert_raises(Rdeflate::DataError) { H::Decoder.new([1, 2]) }
    assert_raises(Rdeflate::DataError) { H::Decoder.new([0, 1], strict: true) }
  end

  def test_empty_code_cannot_decode
    dec = H::Decoder.new([0, 0])
    assert_raises(Rdeflate::DataError) { Rdeflate::BitReader.new("\x00".b).decode(dec) }
  end

  def test_fixed_tables
    assert_equal 9, H::FIXED_LITLEN.max_length
    assert_equal 5, H::FIXED_DIST.max_length
  end
end
