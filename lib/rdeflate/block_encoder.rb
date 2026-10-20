# frozen_string_literal: true

module Rdeflate
  # Writes one DEFLATE block for a list of LZ77 tokens, choosing whichever of
  # stored, fixed-Huffman or dynamic-Huffman encoding is smallest.
  #
  # Tokens are plain Integers: 0..255 is a literal byte, anything larger is a
  # back-reference packed as (distance << 9) | length.
  class BlockEncoder
    include Tables

    STORED_MAX = 65_535

    FIXED_LITLEN_CODES = Huffman.encoder_codes(FIXED_LITLEN_LENGTHS).freeze
    FIXED_DIST_CODES = Huffman.encoder_codes(FIXED_DIST_LENGTHS).freeze

    # Code length code alphabet: extra bits for symbols 16, 17 and 18.
    CL_EXTRA = { 16 => 2, 17 => 3, 18 => 7 }.freeze

    def self.match(length, distance)
      (distance << 9) | length
    end

    attr_reader :stats

    def initialize(writer)
      @writer = writer
      @stats = Hash.new(0) # block type => count, handy for tests and tuning
    end

    # +raw+ must be exactly the input bytes the tokens describe; it is used
    # if a stored block turns out to be the cheapest choice.
    def write_block(tokens, raw, final)
      litfreq = Array.new(286, 0)
      distfreq = Array.new(30, 0)
      extra = 0
      tokens.each do |t|
        if t < 256
          litfreq[t] += 1
        else
          lc = LENGTH_CODE[t & 511]
          dc = DIST_CODE[t >> 9]
          litfreq[257 + lc] += 1
          distfreq[dc] += 1
          extra += LENGTH_EXTRA[lc] + DIST_EXTRA[dc]
        end
      end
      litfreq[256] = 1

      fixed_bits = 3 + extra
      litfreq.each_with_index { |f, sym| fixed_bits += f * FIXED_LITLEN_LENGTHS[sym] }
      distfreq.each { |f| fixed_bits += f * 5 }

      lit_lengths = Huffman.lengths_from_frequencies(litfreq, 15)
      dist_lengths = Huffman.lengths_from_frequencies(distfreq, 15)
      header = DynamicHeader.new(lit_lengths, dist_lengths)
      dynamic_bits = 3 + header.bit_size + extra
      litfreq.each_with_index { |f, sym| dynamic_bits += f * lit_lengths[sym] }
      distfreq.each_with_index { |f, sym| dynamic_bits += f * dist_lengths[sym] }

      stored = stored_bits(raw.bytesize)
      if stored < fixed_bits && stored < dynamic_bits
        write_stored(raw, final)
      elsif fixed_bits <= dynamic_bits
        @stats[:fixed] += 1
        @writer.write_bits(final ? 3 : 2, 3) # BFINAL, BTYPE=01
        write_tokens(tokens, FIXED_LITLEN_CODES, FIXED_LITLEN_LENGTHS, FIXED_DIST_CODES, FIXED_DIST_LENGTHS)
      else
        @stats[:dynamic] += 1
        @writer.write_bits(final ? 5 : 4, 3) # BFINAL, BTYPE=10
        header.write(@writer)
        write_tokens(tokens, Huffman.encoder_codes(lit_lengths), lit_lengths,
                     Huffman.encoder_codes(dist_lengths), dist_lengths)
      end
    end

    # Writes +raw+ as one or more stored blocks (at most 65535 bytes each).
    def write_stored(raw, final)
      w = @writer
      offset = 0
      loop do
        chunk = raw.byteslice(offset, STORED_MAX) || "".b
        offset += chunk.bytesize
        last = offset >= raw.bytesize
        @stats[:stored] += 1
        w.write_bits(final && last ? 1 : 0, 3) # BTYPE=00
        w.align
        w.write_bytes([chunk.bytesize, ~chunk.bytesize & 0xFFFF].pack("v2"))
        w.write_bytes(chunk)
        break if last
      end
    end

    private

    def stored_bits(size)
      blocks = [(size + STORED_MAX - 1) / STORED_MAX, 1].max
      first_pad = (8 - ((@writer.pending_bits + 3) & 7)) & 7
      (blocks * (3 + 32)) + first_pad + ((blocks - 1) * 5) + (8 * size)
    end

    def write_tokens(tokens, lcodes, llens, dcodes, dlens)
      w = @writer
      tokens.each do |t|
        if t < 256
          w.write_bits(lcodes[t], llens[t])
        else
          len = t & 511
          dist = t >> 9
          lc = LENGTH_CODE[len]
          sym = 257 + lc
          n = llens[sym]
          w.write_bits(lcodes[sym] | ((len - LENGTH_BASE[lc]) << n), n + LENGTH_EXTRA[lc])
          dc = DIST_CODE[dist]
          n = dlens[dc]
          w.write_bits(dcodes[dc] | ((dist - DIST_BASE[dc]) << n), n + DIST_EXTRA[dc])
        end
      end
      w.write_bits(lcodes[256], llens[256])
    end

    # The HLIT/HDIST/HCLEN header of a dynamic block, with the code lengths
    # run-length encoded using code length symbols 16 (repeat previous),
    # 17 (short zero run) and 18 (long zero run).
    class DynamicHeader
      include Tables

      attr_reader :bit_size

      def initialize(lit_lengths, dist_lengths)
        @hlit = trimmed_size(lit_lengths, 257)
        @hdist = trimmed_size(dist_lengths, 1)
        @symbols = run_length_encode(lit_lengths[0, @hlit] + dist_lengths[0, @hdist])

        cl_freq = Array.new(19, 0)
        @symbols.each { |sym, _| cl_freq[sym] += 1 }
        @cl_lengths = Huffman.lengths_from_frequencies(cl_freq, 7)
        @cl_codes = Huffman.encoder_codes(@cl_lengths)
        @hclen = 19
        @hclen -= 1 while @hclen > 4 && @cl_lengths[CODE_LENGTH_ORDER[@hclen - 1]].zero?

        @bit_size = 5 + 5 + 4 + (3 * @hclen)
        @symbols.each { |sym, _| @bit_size += @cl_lengths[sym] + CL_EXTRA.fetch(sym, 0) }
      end

      def write(w)
        w.write_bits(@hlit - 257, 5)
        w.write_bits(@hdist - 1, 5)
        w.write_bits(@hclen - 4, 4)
        @hclen.times { |i| w.write_bits(@cl_lengths[CODE_LENGTH_ORDER[i]], 3) }
        @symbols.each do |sym, value|
          w.write_bits(@cl_codes[sym], @cl_lengths[sym])
          w.write_bits(value, CL_EXTRA[sym]) if sym >= 16
        end
      end

      private

      def trimmed_size(lengths, min)
        n = lengths.size
        n -= 1 while n > min && lengths[n - 1].zero?
        n
      end

      # Returns [[symbol, extra_value], ...].
      def run_length_encode(lengths)
        out = []
        i = 0
        n = lengths.size
        while i < n
          len = lengths[i]
          run = 1
          run += 1 while i + run < n && lengths[i + run] == len
          i += run
          if len.zero?
            while run >= 11
              k = [run, 138].min
              out << [18, k - 11]
              run -= k
            end
            if run >= 3
              out << [17, run - 3]
              run = 0
            end
            run.times { out << [0, 0] }
          else
            out << [len, 0]
            run -= 1
            while run >= 3
              k = [run, 6].min
              out << [16, k - 3]
              run -= k
            end
            run.times { out << [len, 0] }
          end
        end
        out
      end
    end
  end
end
