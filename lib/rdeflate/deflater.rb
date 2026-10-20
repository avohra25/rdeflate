# frozen_string_literal: true

module Rdeflate
  # Streaming raw DEFLATE compressor.
  #
  #   d = Deflater.new(level: 9)
  #   out = d.deflate(chunk1) + d.deflate(chunk2) + d.finish
  #
  # Each call returns whatever compressed bytes are complete so far, so large
  # inputs can be compressed without holding all output in memory. Level 0
  # stores; 1-3 use greedy matching; 4-9 lazy matching with longer chains.
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
      @matcher = LZ77.new(level) unless level.zero?
      @stored = String.new(encoding: Encoding::BINARY)
      @held = nil # last parsed block, held back so the final one can be flagged
      @finished = false
    end

    # Block type counts written so far ({stored:, fixed:, dynamic:}).
    def stats
      @encoder.stats
    end

    def deflate(data)
      raise Error, "deflater already finished" if @finished

      if @matcher
        @matcher.feed(data)
        while (block = @matcher.next_tokens(BLOCK_TOKENS))
          emit(block)
        end
      else
        @stored << data.b
        while @stored.bytesize > BlockEncoder::STORED_MAX
          @encoder.write_stored(@stored.byteslice(0, BlockEncoder::STORED_MAX), false)
          @stored = @stored.byteslice(BlockEncoder::STORED_MAX..)
        end
      end
      @writer.take
    end
    alias << deflate

    def finish
      raise Error, "deflater already finished" if @finished

      @finished = true
      if @matcher
        while (block = @matcher.next_tokens(BLOCK_TOKENS, final: true))
          emit(block)
        end
        if @held
          @encoder.write_block(*@held, true)
        else
          @encoder.write_block([], "".b, true)
        end
      else
        @encoder.write_stored(@stored, true)
      end
      @writer.align
      @writer.take
    end

    private

    def emit(block)
      @encoder.write_block(*@held, false) if @held
      @held = block
    end
  end
end
