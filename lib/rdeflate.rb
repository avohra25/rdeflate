# frozen_string_literal: true

require_relative "rdeflate/version"
require_relative "rdeflate/errors"
require_relative "rdeflate/checksums"
require_relative "rdeflate/tables"
require_relative "rdeflate/huffman"
require_relative "rdeflate/bit_reader"
require_relative "rdeflate/bit_writer"
require_relative "rdeflate/inflater"
require_relative "rdeflate/block_encoder"
require_relative "rdeflate/deflater"

# Pure-Ruby DEFLATE (RFC 1951) with zlib (RFC 1950) and gzip (RFC 1952)
# containers.
module Rdeflate
  module_function

  # Compresses +data+ into a raw DEFLATE stream (no header or checksum).
  def deflate(data, level: 6)
    d = Deflater.new(level: level)
    d.deflate(data) << d.finish
  end

  # Decompresses a raw DEFLATE stream. Bytes after the final block are ignored.
  def inflate(data)
    Inflater.new(data).inflate
  end
end
