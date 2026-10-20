# frozen_string_literal: true

module Rdeflate
  # Constant tables from RFC 1951 section 3.2.5 and 3.2.6.
  module Tables
    LENGTH_BASE = [
      3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
      35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
    ].freeze
    LENGTH_EXTRA = [
      0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
      3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
    ].freeze
    DIST_BASE = [
      1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
      257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12_289, 16_385, 24_577
    ].freeze
    DIST_EXTRA = [
      0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
      7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
    ].freeze

    # Order in which code length code lengths are transmitted.
    CODE_LENGTH_ORDER = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15].freeze

    # Fixed Huffman code lengths (section 3.2.6). Symbols 286/287 and
    # distance codes 30/31 take part in the code but never occur in valid data.
    FIXED_LITLEN_LENGTHS = (Array.new(144, 8) + Array.new(112, 9) + Array.new(24, 7) + Array.new(8, 8)).freeze
    FIXED_DIST_LENGTHS = Array.new(32, 5).freeze

    # LENGTH_CODE[len] -> index into LENGTH_BASE for 3 <= len <= 258.
    LENGTH_CODE = Array.new(259, 0).tap do |table|
      LENGTH_BASE.each_with_index do |base, code|
        (base...(base + (1 << LENGTH_EXTRA[code]))).each { |len| table[len] = code if len <= 258 }
      end
    end.freeze

    # DIST_CODE[dist] -> index into DIST_BASE for 1 <= dist <= 32768.
    DIST_CODE = Array.new(32_769, 0).tap do |table|
      DIST_BASE.each_with_index do |base, code|
        (base...(base + (1 << DIST_EXTRA[code]))).each { |dist| table[dist] = code }
      end
    end.freeze
  end
end
