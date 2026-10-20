# frozen_string_literal: true

module Rdeflate
  # Adler-32 (RFC 1950) and CRC-32 (ISO 3309, as used by gzip/PNG/zip).
  #
  # Both functions take an optional running value so they can be fed in
  # chunks, mirroring Zlib.adler32 / Zlib.crc32:
  #
  #   crc = Checksum.crc32("hello ")
  #   crc = Checksum.crc32("world", crc)
  module Checksum
    ADLER_MOD = 65_521
    # Largest n such that 255n(n+1)/2 + (n+1)(MOD-1) fits in 32 bits; lets us
    # defer the modulo the same way zlib does.
    ADLER_NMAX = 5552

    CRC_TABLE = Array.new(256) do |n|
      c = n
      8.times { c = c.odd? ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
      c
    end.freeze

    module_function

    def adler32(data, adler = 1)
      a = adler & 0xFFFF
      b = (adler >> 16) & 0xFFFF
      pos = 0
      size = data.bytesize
      while pos < size
        data.byteslice(pos, ADLER_NMAX).each_byte do |byte|
          a += byte
          b += a
        end
        a %= ADLER_MOD
        b %= ADLER_MOD
        pos += ADLER_NMAX
      end
      (b << 16) | a
    end

    def crc32(data, crc = 0)
      c = crc ^ 0xFFFF_FFFF
      table = CRC_TABLE
      data.each_byte { |byte| c = table[(c ^ byte) & 0xFF] ^ (c >> 8) }
      c ^ 0xFFFF_FFFF
    end
  end
end
