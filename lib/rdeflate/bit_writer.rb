# frozen_string_literal: true

module Rdeflate
  # Packs bit fields LSB first into a binary string (the inverse of BitReader).
  class BitWriter
    def initialize
      @out = String.new(encoding: Encoding::BINARY)
      @buf = 0
      @cnt = 0
    end

    # Number of bits written past the last byte boundary (0..7).
    def pending_bits
      @cnt
    end

    # Writes the low +n+ bits of +value+, LSB first.
    def write_bits(value, n)
      @buf |= value << @cnt
      @cnt += n
      while @cnt >= 8
        @out << (@buf & 0xFF)
        @buf >>= 8
        @cnt -= 8
      end
      self
    end

    # Writes a Huffman code given as its canonical (MSB-first) value.
    def write_code(code, length)
      write_bits(Huffman.reverse(code, length), length)
    end

    # Pads with zero bits to the next byte boundary.
    def align
      if @cnt.positive?
        @out << (@buf & 0xFF)
        @buf = 0
        @cnt = 0
      end
      self
    end

    # Appends raw bytes; only valid on a byte boundary.
    def write_bytes(str)
      raise ArgumentError, "write_bytes requires byte alignment" unless @cnt.zero?

      @out << str.b
      self
    end

    # Returns the completed bytes written so far and clears them; bits of a
    # partial final byte stay buffered.
    def take
      out = @out
      @out = String.new(encoding: Encoding::BINARY)
      out
    end

    # All completed bytes (without the partial byte).
    def string
      @out
    end
  end
end
