# frozen_string_literal: true

module Rdeflate
  # Canonical Huffman codes and table-driven decoding.
  module Huffman
    MAX_BITS = 15

    module_function

    # Reverses the low +length+ bits of +code+.
    def reverse(code, length)
      result = 0
      length.times do
        result = (result << 1) | (code & 1)
        code >>= 1
      end
      result
    end

    # Assigns canonical codes (RFC 1951 3.2.2) to a list of code lengths.
    # Returns MSB-first code values; unused symbols (length 0) get 0.
    def canonical_codes(lengths)
      max = lengths.max || 0
      bl_count = Array.new(max + 1, 0)
      lengths.each { |len| bl_count[len] += 1 if len.positive? }
      next_code = Array.new(max + 1, 0)
      code = 0
      (1..max).each do |bits|
        code = (code + bl_count[bits - 1]) << 1
        next_code[bits] = code
      end
      lengths.map do |len|
        next 0 if len.zero?

        c = next_code[len]
        next_code[len] += 1
        c
      end
    end

    # A table-driven decoder. The table is indexed by the next +max_length+
    # input bits (LSB first) and each entry packs (symbol << 4) | code_length;
    # an entry of 0 marks a bit pattern that no code matches.
    class Decoder
      attr_reader :table, :max_length, :mask

      # +strict+ rejects incomplete codes (required for the code length
      # code). Otherwise, like zlib, the only incomplete code accepted is a
      # single code of length one; an all-zero set of lengths is accepted but
      # any attempt to decode with it fails.
      def initialize(lengths, strict: false)
        count = Array.new(MAX_BITS + 1, 0)
        lengths.each do |len|
          raise DataError, "invalid code length #{len}" if len.negative? || len > MAX_BITS

          count[len] += 1
        end
        count[0] = 0
        max = MAX_BITS
        max -= 1 while max.positive? && count[max].zero?

        if max.zero?
          @max_length = 0
          @mask = 0
          @table = [0].freeze
          return
        end

        left = 1
        (1..MAX_BITS).each do |len|
          left = (left << 1) - count[len]
          raise DataError, "invalid Huffman code lengths (over-subscribed)" if left.negative?
        end
        raise DataError, "invalid Huffman code lengths (incomplete)" if left.positive? && (strict || max != 1)

        size = 1 << max
        table = Array.new(size, 0)
        Huffman.canonical_codes(lengths).each_with_index do |code, sym|
          len = lengths[sym]
          next if len.zero?

          entry = (sym << 4) | len
          step = 1 << len
          idx = Huffman.reverse(code, len)
          while idx < size
            table[idx] = entry
            idx += step
          end
        end
        @table = table.freeze
        @max_length = max
        @mask = size - 1
      end
    end

    FIXED_LITLEN = Decoder.new(Tables::FIXED_LITLEN_LENGTHS)
    FIXED_DIST = Decoder.new(Tables::FIXED_DIST_LENGTHS)
  end
end
