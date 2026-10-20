# frozen_string_literal: true

module Rdeflate
  # Base class for every error raised by rdeflate.
  class Error < StandardError; end

  # The compressed data is malformed (bad block type, invalid code, ...).
  class DataError < Error; end

  # The compressed data ended before the stream was complete.
  class TruncatedError < DataError; end

  # A container checksum (Adler-32, CRC-32) or length check failed.
  class ChecksumError < DataError; end
end
