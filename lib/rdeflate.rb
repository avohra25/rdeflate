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
require_relative "rdeflate/lz77"
require_relative "rdeflate/deflater"
require_relative "rdeflate/zlib_format"
require_relative "rdeflate/gzip_format"
require_relative "rdeflate/stream"

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

  # zlib-wrapped DEFLATE (what Zlib::Deflate.deflate produces).
  def zlib_compress(data, level: 6)
    ZlibFormat.compress(data, level: level)
  end

  def zlib_decompress(data)
    ZlibFormat.decompress(data)
  end

  # A single-member gzip file. Header options: filename:, comment:, mtime:,
  # os:, extra:, text:, header_crc:.
  def gzip(data, level: 6, **header)
    GzipFormat.compress(data, level: level, **header)
  end

  # Decompresses every member of a gzip file and concatenates the results.
  def gunzip(data)
    GzipFormat.decompress(data)
  end

  FORMATS = %i[gzip zlib raw].freeze

  def compress(data, format: :gzip, level: 6)
    case format
    when :gzip then gzip(data, level: level)
    when :zlib then zlib_compress(data, level: level)
    when :raw then deflate(data, level: level)
    else raise ArgumentError, "unknown format #{format.inspect} (expected one of #{FORMATS.join(", ")})"
    end
  end

  # Decompresses +data+; with format: :auto the container is detected from
  # the first bytes (gzip magic, then a valid zlib header, else raw).
  def decompress(data, format: :auto)
    format = detect_format(data) if format == :auto
    case format
    when :gzip then gunzip(data)
    when :zlib then zlib_decompress(data)
    when :raw then inflate(data)
    else raise ArgumentError, "unknown format #{format.inspect}"
    end
  end

  def detect_format(data)
    if GzipFormat.header?(data) then :gzip
    elsif ZlibFormat.header?(data) then :zlib
    else :raw
    end
  end
end
