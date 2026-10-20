# frozen_string_literal: true

require_relative "test_helper"

class ChecksumTest < Minitest::Test
  C = Rdeflate::Checksum

  def test_known_values
    assert_equal 1, C.adler32("")
    assert_equal 0, C.crc32("")
    assert_equal 0x11E60398, C.adler32("Wikipedia")
    assert_equal 0xCBF43926, C.crc32("123456789")
  end

  def test_matches_zlib_on_samples
    sample_inputs.each do |name, data|
      assert_equal Zlib.adler32(data), C.adler32(data), "adler32 #{name}"
      assert_equal Zlib.crc32(data), C.crc32(data), "crc32 #{name}"
    end
  end

  def test_incremental_updates
    data = random_text(50_000)
    adler = 1
    crc = 0
    data.bytes.each_slice(777) do |chunk|
      s = chunk.pack("C*")
      adler = C.adler32(s, adler)
      crc = C.crc32(s, crc)
    end
    assert_equal Zlib.adler32(data), adler
    assert_equal Zlib.crc32(data), crc
  end

  def test_adler_modulo_boundaries
    # 0xFF runs longer than NMAX force the deferred modulo to matter.
    [5551, 5552, 5553, 100_000].each do |n|
      data = ("\xFF" * n).b
      assert_equal Zlib.adler32(data), C.adler32(data), "n=#{n}"
    end
  end
end
