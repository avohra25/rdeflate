# frozen_string_literal: true

module Rdeflate
  # Reads a byte string as a little-endian bit stream, the way DEFLATE packs
  # it: data elements start at the least significant bit of each byte, and
  # Huffman codes are stored most-significant-bit first (which is why decode
  # tables are indexed by bit-reversed codes).
  class BitReader
    attr_reader :pos

    def initialize(data, pos = 0)
      @data = data.encoding == Encoding::BINARY ? data : data.dup.force_encoding(Encoding::BINARY)
      @pos = pos   # next byte to load into the bit buffer
      @buf = 0     # pending bits, LSB first
      @cnt = 0     # number of valid bits in @buf
    end

    # Reads +n+ bits (0..32) as an unsigned integer, LSB first.
    def bits(n)
      return 0 if n.zero?

      while @cnt < n
        byte = @data.getbyte(@pos) or raise TruncatedError, "unexpected end of compressed data"
        @buf |= byte << @cnt
        @cnt += 8
        @pos += 1
      end
      value = @buf & ((1 << n) - 1)
      @buf >>= n
      @cnt -= n
      value
    end

    # Decodes one symbol using a Huffman::Decoder table.
    def decode(decoder)
      max = decoder.max_length
      while @cnt < max
        byte = @data.getbyte(@pos) or break
        @buf |= byte << @cnt
        @cnt += 8
        @pos += 1
      end
      entry = decoder.table[@buf & decoder.mask]
      len = entry & 15
      if len.zero? || len > @cnt
        raise TruncatedError, "unexpected end of compressed data" if @cnt < max

        raise DataError, "invalid Huffman code"
      end
      @buf >>= len
      @cnt -= len
      entry >> 4
    end

    # Discards bits up to the next byte boundary and hands any whole bytes
    # still sitting in the bit buffer back to the byte stream, so that
    # #read_bytes and #pos refer to the true byte position.
    def align
      @cnt -= @cnt & 7
      @pos -= @cnt >> 3
      @buf = 0
      @cnt = 0
    end

    # Reads +n+ raw bytes; only valid on a byte boundary (after #align).
    def read_bytes(n)
      raise ArgumentError, "read_bytes requires byte alignment" unless @cnt.zero?
      raise TruncatedError, "unexpected end of compressed data" if @pos + n > @data.bytesize

      str = @data.byteslice(@pos, n)
      @pos += n
      str
    end
  end
end
