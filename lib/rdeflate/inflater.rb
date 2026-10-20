# frozen_string_literal: true

module Rdeflate
  # Decompresses a raw DEFLATE stream (RFC 1951).
  #
  #   Inflater.new(data).inflate          # => decompressed bytes
  #
  # Decoding starts at byte +pos+ and stops after the block marked final;
  # #end_pos then tells container parsers where the trailer begins.
  class Inflater
    include Tables

    attr_reader :end_pos

    def self.inflate(data, pos = 0)
      new(data, pos).inflate
    end

    def initialize(data, pos = 0)
      @reader = BitReader.new(data, pos)
      @end_pos = nil
    end

    def inflate
      out = String.new(encoding: Encoding::BINARY)
      r = @reader
      loop do
        final = r.bits(1)
        case r.bits(2)
        when 0 then inflate_stored(out)
        when 1 then inflate_codes(out, Huffman::FIXED_LITLEN, Huffman::FIXED_DIST)
        when 2 then inflate_codes(out, *read_dynamic_tables)
        else raise DataError, "invalid block type"
        end
        break if final == 1
      end
      r.align
      @end_pos = r.pos
      out
    end

    private

    def inflate_stored(out)
      r = @reader
      r.align
      len, nlen = r.read_bytes(4).unpack("v2")
      raise DataError, "invalid stored block lengths" unless len == (~nlen & 0xFFFF)

      out << r.read_bytes(len)
    end

    def read_dynamic_tables
      r = @reader
      hlit = r.bits(5) + 257
      hdist = r.bits(5) + 1
      hclen = r.bits(4) + 4
      raise DataError, "too many length or distance symbols" if hlit > 286 || hdist > 30

      cl_lengths = Array.new(19, 0)
      hclen.times { |i| cl_lengths[CODE_LENGTH_ORDER[i]] = r.bits(3) }
      cl = Huffman::Decoder.new(cl_lengths, strict: true)

      total = hlit + hdist
      lengths = []
      while lengths.size < total
        sym = r.decode(cl)
        if sym < 16
          lengths << sym
        else
          case sym
          when 16
            raise DataError, "repeat code with no previous length" if lengths.empty?

            value = lengths.last
            repeat = 3 + r.bits(2)
          when 17
            value = 0
            repeat = 3 + r.bits(3)
          else
            value = 0
            repeat = 11 + r.bits(7)
          end
          raise DataError, "too many code lengths" if lengths.size + repeat > total

          repeat.times { lengths << value }
        end
      end

      lit_lengths = lengths[0, hlit]
      raise DataError, "missing end-of-block code" if lit_lengths[256].zero?

      [Huffman::Decoder.new(lit_lengths), Huffman::Decoder.new(lengths[hlit, hdist])]
    end

    def inflate_codes(out, lit, dist)
      r = @reader
      loop do
        sym = r.decode(lit)
        if sym < 256
          out << sym
        elsif sym == 256
          return
        else
          sym -= 257
          raise DataError, "invalid literal/length code" if sym >= 29

          len = LENGTH_BASE[sym] + r.bits(LENGTH_EXTRA[sym])
          dsym = r.decode(dist)
          raise DataError, "invalid distance code" if dsym >= 30

          d = DIST_BASE[dsym] + r.bits(DIST_EXTRA[dsym])
          size = out.bytesize
          raise DataError, "invalid distance too far back" if d > size

          if len <= d
            out << out.byteslice(size - d, len)
          else
            # Overlapping copy: the match repeats the last +d+ bytes.
            chunk = out.byteslice(size - d, d)
            out << (chunk * (len / d)) << chunk.byteslice(0, len % d)
          end
        end
      end
    end
  end
end
