# frozen_string_literal: true

module Rdeflate
  # The gzip container (RFC 1952). A file is one or more members, each with
  # a header (optional file name, comment, mtime, extra field, header CRC),
  # a raw DEFLATE stream, and a CRC-32 + length trailer.
  module GzipFormat
    MAGIC = "\x1F\x8B".b.freeze
    FTEXT = 0x01
    FHCRC = 0x02
    FEXTRA = 0x04
    FNAME = 0x08
    FCOMMENT = 0x10
    RESERVED = 0xE0
    OS_UNIX = 3
    OS_UNKNOWN = 255

    # One decoded member: the data plus its header fields.
    Member = Struct.new(:data, :filename, :comment, :mtime, :os, :extra, :text,
                        :compressed_size, keyword_init: true)

    module_function

    # Builds a member header. +mtime+ may be a Time or Integer (0 = unknown).
    def header(level: 6, filename: nil, comment: nil, mtime: 0, os: OS_UNIX, extra: nil, text: false,
               header_crc: false)
      flags = 0
      flags |= FTEXT if text
      flags |= FHCRC if header_crc
      flags |= FEXTRA if extra
      flags |= FNAME if filename
      flags |= FCOMMENT if comment
      xfl = if level == 9 then 2
            elsif level == 1 then 4
            else 0
            end
      h = MAGIC.dup
      h << [8, flags, mtime.to_i & 0xFFFF_FFFF, xfl, os].pack("CCVCC")
      if extra
        raise ArgumentError, "gzip extra field is limited to 65535 bytes" if extra.bytesize > 0xFFFF

        h << [extra.bytesize].pack("v") << extra.b
      end
      h << zero_terminated(filename, "filename") if filename
      h << zero_terminated(comment, "comment") if comment
      h << [Checksum.crc32(h) & 0xFFFF].pack("v") if header_crc
      h
    end

    def trailer(crc, size)
      [crc, size & 0xFFFF_FFFF].pack("VV")
    end

    # Compresses +data+ into a single gzip member.
    def compress(data, level: 6, **header_opts)
      data = data.b
      header(level: level, **header_opts) << Rdeflate.deflate(data, level: level) <<
        trailer(Checksum.crc32(data), data.bytesize)
    end

    # Decompresses all members and returns their concatenated data.
    def decompress(data)
      out = String.new(encoding: Encoding::BINARY)
      each_member(data) { |m| out << m.data }
      out
    end

    def members(data)
      enum_for(:each_member, data).to_a
    end

    # Yields each Member in turn. Trailing zero padding (as left by tape
    # drives and some tools) is ignored; any other trailing bytes are an
    # error, as is an empty input.
    def each_member(data)
      data = data.b
      pos = 0
      loop do
        member, pos = read_member(data, pos)
        yield member
        break if pos == data.bytesize
        break if data.byteslice(pos..).delete("\0").empty?
        raise DataError, "trailing garbage after gzip member" unless data.byteslice(pos, 2) == MAGIC
      end
    end

    def read_member(data, start)
      raise TruncatedError, "gzip header truncated" if data.bytesize < start + 10
      raise DataError, "not in gzip format (bad magic)" unless data.byteslice(start, 2) == MAGIC

      method, flags, mtime, _xfl, os = data.byteslice(start + 2, 8).unpack("CCVCC")
      raise DataError, "unknown compression method #{method}" unless method == 8
      raise DataError, "reserved gzip flags set" if flags & RESERVED != 0

      pos = start + 10
      extra = nil
      if flags & FEXTRA != 0
        raise TruncatedError, "gzip header truncated" if data.bytesize < pos + 2

        xlen = data.byteslice(pos, 2).unpack1("v")
        raise TruncatedError, "gzip header truncated" if data.bytesize < pos + 2 + xlen

        extra = data.byteslice(pos + 2, xlen)
        pos += 2 + xlen
      end
      filename, pos = read_string(data, pos) if flags & FNAME != 0
      comment, pos = read_string(data, pos) if flags & FCOMMENT != 0
      if flags & FHCRC != 0
        raise TruncatedError, "gzip header truncated" if data.bytesize < pos + 2

        expected = data.byteslice(pos, 2).unpack1("v")
        raise ChecksumError, "gzip header CRC mismatch" if expected != (Checksum.crc32(data.byteslice(start, pos - start)) & 0xFFFF)

        pos += 2
      end

      inflater = Inflater.new(data, pos)
      body = inflater.inflate
      tail = inflater.end_pos
      raise TruncatedError, "gzip trailer truncated" if data.bytesize < tail + 8

      crc, isize = data.byteslice(tail, 8).unpack("VV")
      actual = Checksum.crc32(body)
      raise ChecksumError, format("CRC-32 mismatch (expected %08x, got %08x)", crc, actual) if crc != actual
      raise ChecksumError, "length mismatch (expected #{isize}, got #{body.bytesize})" if isize != (body.bytesize & 0xFFFF_FFFF)

      member = Member.new(data: body, filename: filename, comment: comment, mtime: mtime, os: os, extra: extra,
                          text: flags & FTEXT != 0, compressed_size: tail + 8 - start)
      [member, tail + 8]
    end

    def header?(data)
      data.byteslice(0, 2) == MAGIC
    end

    def zero_terminated(str, what)
      bytes = str.to_s.encode(Encoding::ISO_8859_1, invalid: :replace, undef: :replace).b
      raise ArgumentError, "gzip #{what} must not contain NUL bytes" if bytes.include?("\0")

      bytes << "\0"
    end
    private_class_method :zero_terminated

    def read_string(data, pos)
      nul = data.index("\0", pos) or raise TruncatedError, "gzip header truncated"
      [data.byteslice(pos, nul - pos).force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8), nul + 1]
    end
    private_class_method :read_string
  end
end
