# frozen_string_literal: true

module Rdeflate
  # Streaming raw DEFLATE compressor.
  #
  #   d = Deflater.new(level: 9)
  #   out = d.deflate(chunk1) + d.deflate(chunk2) + d.finish
  #
  # Each call returns whatever compressed bytes are complete so far, so large
  # inputs can be compressed without holding all output in memory. Level 0
  # stores; for now levels 1-9 entropy-code literals only (no LZ77 yet), with
  # each block written as stored, fixed or dynamic, whichever is smallest.
  class Deflater
    # Tokens per block. Smaller blocks adapt faster to changing data, larger
    # blocks amortise the dynamic Huffman header (zlib uses 16K symbols).
    BLOCK_TOKENS = 16_384

    attr_reader :level

    def initialize(level: 6)
      unless level.is_a?(Integer) && level.between?(0, 9)
        raise ArgumentError, "level must be an Integer in 0..9, got #{level.inspect}"
      end

      @level = level
      @writer = BitWriter.new
      @encoder = BlockEncoder.new(@writer)
      @pending = String.new(encoding: Encoding::BINARY)
      @held = nil # last parsed block, held back so the final one can be flagged
      @finished = false
    end

    # Block type counts written so far ({stored:, fixed:, dynamic:}).
    def stats
      @encoder.stats
    end

    def deflate(data)
      raise Error, "deflater already finished" if @finished

      @pending << data.b
      chunk = @level.zero? ? BlockEncoder::STORED_MAX : BLOCK_TOKENS
      while @pending.bytesize > chunk
        flush_chunk(@pending.byteslice(0, chunk))
        @pending = @pending.byteslice(chunk..)
      end
      @writer.take
    end
    alias << deflate

    def finish
      raise Error, "deflater already finished" if @finished

      @finished = true
      if @level.zero?
        @encoder.write_stored(@pending, true)
      else
        flush_chunk(@pending) unless @pending.empty?
        if @held
          @encoder.write_block(*@held, true)
        else
          @encoder.write_block([], "".b, true)
        end
      end
      @writer.align
      @writer.take
    end

    private

    def flush_chunk(raw)
      if @level.zero?
        @encoder.write_stored(raw, false)
      else
        @encoder.write_block(*@held, false) if @held
        @held = [raw.bytes, raw]
      end
    end
  end
end
