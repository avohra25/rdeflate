# frozen_string_literal: true

module Rdeflate
  # The zlib container (RFC 1950): a two-byte header, a raw DEFLATE stream
  # and a big-endian Adler-32 of the uncompressed data.
  module ZlibFormat
    CM_DEFLATE = 8

    module_function

    def header(level)
      cmf = (7 << 4) | CM_DEFLATE # 32 KiB window
      flevel = if level <= 1 then 0
               elsif level <= 5 then 1
               elsif level == 6 then 2
               else 3
               end
      flg = flevel << 6
      flg |= (31 - (((cmf << 8) | flg) % 31)) % 31
      [cmf, flg].pack("CC")
    end

    def compress(data, level: 6)
      data = data.b
      header(level) << Rdeflate.deflate(data, level: level) << [Checksum.adler32(data)].pack("N")
    end

    # Returns [decompressed, end_pos] for a zlib stream starting at +pos+.
    def decompress_at(data, pos = 0)
      raise TruncatedError, "zlib header truncated" if data.bytesize < pos + 2

      cmf = data.getbyte(pos)
      flg = data.getbyte(pos + 1)
      raise DataError, "incorrect zlib header check" unless ((cmf << 8) | flg) % 31 == 0
      raise DataError, "unknown compression method #{cmf & 15}" unless (cmf & 15) == CM_DEFLATE
      raise DataError, "invalid window size" if (cmf >> 4) > 7
      raise Error, "preset dictionaries are not supported" if flg & 0x20 != 0

      inflater = Inflater.new(data, pos + 2)
      out = inflater.inflate
      tail = inflater.end_pos
      raise TruncatedError, "zlib trailer truncated" if data.bytesize < tail + 4

      expected = data.byteslice(tail, 4).unpack1("N")
      actual = Checksum.adler32(out)
      raise ChecksumError, format("Adler-32 mismatch (expected %08x, got %08x)", expected, actual) if expected != actual

      [out, tail + 4]
    end

    # Decompresses exactly one zlib stream; trailing bytes are an error.
    def decompress(data)
      out, end_pos = decompress_at(data)
      raise DataError, "trailing data after zlib stream" if end_pos != data.bytesize

      out
    end

    # Heuristic used by Rdeflate.decompress(format: :auto).
    def header?(data)
      data.bytesize >= 2 && (data.getbyte(0) & 15) == CM_DEFLATE && (data.getbyte(0) >> 4) <= 7 &&
        ((data.getbyte(0) << 8) | data.getbyte(1)) % 31 == 0
    end
  end
end
