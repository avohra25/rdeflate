# frozen_string_literal: true

module Rdeflate
  # IO-friendly gzip writer: compresses as you write, emitting complete
  # DEFLATE blocks to the underlying IO, then the CRC-32/size trailer on
  # #close. Works with anything responding to #write.
  #
  #   Rdeflate::GzipWriter.open("log.gz", level: 9) do |gz|
  #     gz.puts "hello"
  #     gz << "world\n"
  #   end
  class GzipWriter
    def self.open(path, **opts)
      file = File.open(path, "wb")
      gz = new(file, close_io: true, **opts)
      return gz unless block_given?

      begin
        yield gz
      ensure
        gz.close unless gz.closed?
      end
    end

    def initialize(io, level: 6, filename: nil, comment: nil, mtime: 0, close_io: false)
      @io = io
      @close_io = close_io
      @deflater = Deflater.new(level: level)
      @crc = 0
      @size = 0
      @closed = false
      @io.write(GzipFormat.header(level: level, filename: filename, comment: comment, mtime: mtime))
    end

    def write(*strings)
      raise IOError, "closed gzip stream" if @closed

      strings.sum do |s|
        s = s.to_s.b
        @crc = Checksum.crc32(s, @crc)
        @size += s.bytesize
        out = @deflater.deflate(s)
        @io.write(out) unless out.empty?
        s.bytesize
      end
    end

    def <<(str)
      write(str)
      self
    end

    def print(*args)
      write(*args)
      nil
    end

    def puts(*lines)
      lines = [""] if lines.empty?
      lines.flatten.each { |l| write(l.to_s.end_with?("\n") ? l.to_s : "#{l}\n") }
      nil
    end

    def closed?
      @closed
    end

    # Writes the final block and trailer. Returns the underlying IO.
    def finish
      raise IOError, "closed gzip stream" if @closed

      @closed = true
      @io.write(@deflater.finish << GzipFormat.trailer(@crc, @size))
      @io
    end

    def close
      io = finish
      io.close if @close_io
      io
    end
  end

  # Reads a whole gzip file (all members) from an IO or path.
  class GzipReader
    def self.open(path)
      reader = new(File.binread(path))
      block_given? ? yield(reader) : reader
    end

    attr_reader :members

    def initialize(io_or_string)
      data = io_or_string.respond_to?(:read) ? io_or_string.read : io_or_string
      @members = GzipFormat.members(data.b)
    end

    def read
      @members.map(&:data).join.b
    end

    def each_line(sep = $/, &block)
      return enum_for(:each_line, sep) unless block

      read.each_line(sep, &block)
    end

    def filename
      @members.first&.filename
    end

    def mtime
      t = @members.first&.mtime
      t && Time.at(t)
    end
  end
end
