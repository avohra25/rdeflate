# frozen_string_literal: true

require "optparse"
require_relative "../rdeflate"

module Rdeflate
  # Command-line front end used by bin/rdeflate.
  #
  #   rdeflate compress [-0..-9] [--gzip|--zlib|--raw] [-c|-o OUT] [FILE...]
  #   rdeflate decompress [--format auto|gzip|zlib|raw] [-c|-o OUT] [FILE...]
  #   rdeflate info FILE...
  #
  # Input files are never deleted. Without -c/-o, "compress a.txt" writes
  # a.txt.gz (.zz for zlib, .deflate for raw) and "decompress a.txt.gz"
  # writes a.txt. With no files, stdin is filtered to stdout.
  class CLI
    SUFFIXES = { gzip: ".gz", zlib: ".zz", raw: ".deflate" }.freeze
    COMMANDS = {
      "compress" => :compress, "c" => :compress,
      "decompress" => :decompress, "d" => :decompress,
      "info" => :info, "i" => :info
    }.freeze

    class UsageError < StandardError; end

    def self.start(argv = ARGV)
      exit new(argv).run
    end

    def initialize(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      @argv = argv.dup
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @options = { level: 6, format: nil, stdout: false, output: nil, name: true, force: false, verbose: false }
    end

    def run
      status = catch(:done) do
        command = COMMANDS[@argv.first] && COMMANDS[@argv.shift]
        @argv = @argv.reject { |a| a.match?(/\A-\d\z/) && (@options[:level] = a[1].to_i) }
        files = parser.parse(@argv)
        raise UsageError, "missing command (compress, decompress or info)" unless command

        send(command, files)
        nil
      end
      status || 0
    rescue UsageError, OptionParser::ParseError => e
      @stderr.puts "rdeflate: #{e.message}"
      @stderr.puts parser.banner
      2
    rescue Rdeflate::Error, SystemCallError, IOError, ArgumentError => e
      @stderr.puts "rdeflate: #{e.message}"
      1
    end

    private

    def parser
      @parser ||= OptionParser.new do |o|
        o.banner = "Usage: rdeflate {compress|decompress|info} [options] [FILE...]"
        o.separator ""
        o.separator "Options:"
        o.on("-l", "--level N", Integer, "Compression level 0 (store) .. 9 (best), default 6",
             "(shorthands: -0 .. -9)") do |n|
          raise UsageError, "level must be 0-9" unless n.between?(0, 9)

          @options[:level] = n
        end
        o.on("--format FORMAT", %w[gzip zlib raw auto], "Container: gzip (default), zlib, raw, auto (decompress)") do |f|
          @options[:format] = f.to_sym
        end
        o.on("--gzip", "Same as --format gzip") { @options[:format] = :gzip }
        o.on("--zlib", "Same as --format zlib") { @options[:format] = :zlib }
        o.on("--raw", "Same as --format raw") { @options[:format] = :raw }
        o.on("-c", "--stdout", "Write to standard output") { @options[:stdout] = true }
        o.on("-o", "--output PATH", "Write to PATH (single input only)") { |p| @options[:output] = p }
        o.on("-n", "--no-name", "Do not store the file name and mtime in gzip headers") { @options[:name] = false }
        o.on("-f", "--force", "Overwrite existing output files") { @options[:force] = true }
        o.on("-v", "--verbose", "Report sizes and ratio on stderr") { @options[:verbose] = true }
        o.on("--version", "Print version") do
          @stdout.puts "rdeflate #{VERSION}"
          throw :done
        end
        o.on("-h", "--help", "Show this help") do
          @stdout.puts o
          throw :done
        end
      end
    end

    def compress(files)
      format = @options[:format] || :gzip
      raise UsageError, "--format auto only makes sense for decompress" if format == :auto

      each_input(files) do |name, data|
        out = if format == :gzip
                header = {}
                if @options[:name] && name
                  header[:filename] = File.basename(name)
                  header[:mtime] = File.mtime(name).to_i
                end
                Rdeflate.gzip(data, level: @options[:level], **header)
              else
                Rdeflate.compress(data, format: format, level: @options[:level])
              end
        emit(name, name && "#{name}#{SUFFIXES.fetch(format)}", out, data.bytesize, out.bytesize)
      end
    end

    def decompress(files)
      format = @options[:format] || :auto
      each_input(files) do |name, data|
        fmt = format == :auto ? Rdeflate.detect_format(data) : format
        out = Rdeflate.decompress(data, format: fmt)
        emit(name, name && strip_suffix(name), out, out.bytesize, data.bytesize)
      end
    end

    def info(files)
      raise UsageError, "info needs at least one FILE" if files.empty?

      files.each do |path|
        data = File.binread(path)
        fmt = @options[:format] && @options[:format] != :auto ? @options[:format] : Rdeflate.detect_format(data)
        @stdout.puts "#{path}: #{fmt}"
        case fmt
        when :gzip
          GzipFormat.members(data).each_with_index do |m, i|
            fields = ["member #{i + 1}:", "#{m.compressed_size} -> #{m.data.bytesize} bytes",
                      "(#{ratio(m.data.bytesize, m.compressed_size)})"]
            fields << "name=#{m.filename.inspect}" if m.filename
            fields << "mtime=#{Time.at(m.mtime).utc.strftime("%Y-%m-%dT%H:%M:%SZ")}" if m.mtime.positive?
            fields << "comment=#{m.comment.inspect}" if m.comment
            fields << "os=#{m.os}"
            @stdout.puts "  #{fields.join(" ")}"
          end
        else
          out = Rdeflate.decompress(data, format: fmt)
          @stdout.puts "  #{data.bytesize} -> #{out.bytesize} bytes (#{ratio(out.bytesize, data.bytesize)})"
        end
      end
    end

    def each_input(files)
      if (@options[:output] || nil) && files.size > 1
        raise UsageError, "--output can only be used with a single input"
      end

      if files.empty? || files == ["-"]
        yield nil, @stdin.binmode.read
      else
        files.each do |path|
          yield path, File.binread(path)
        rescue Rdeflate::Error => e
          raise e.class, "#{path}: #{e.message}"
        end
      end
    end

    def emit(input_name, default_output, data, original, compressed)
      target = if @options[:stdout] then nil
               elsif @options[:output] then @options[:output]
               elsif input_name then default_output || raise(Rdeflate::Error, "#{input_name}: unknown suffix, use -c or -o")
               end
      if target.nil? || target == "-"
        @stdout.binmode if @stdout.respond_to?(:binmode)
        @stdout.write(data)
      else
        raise Rdeflate::Error, "#{target} already exists (use --force to overwrite)" if File.exist?(target) && !@options[:force]

        File.binwrite(target, data)
      end
      return unless @options[:verbose]

      @stderr.puts "#{input_name || "stdin"}: #{original} -> #{compressed} bytes (#{ratio(original, compressed)})" \
                   "#{target ? " -> #{target}" : ""}"
    end

    def strip_suffix(name)
      return name.delete_suffix(".tgz") + ".tar" if name.end_with?(".tgz")

      suffix = SUFFIXES.values.find { |s| name.end_with?(s) && name.size > s.size }
      suffix && name.delete_suffix(suffix)
    end

    def ratio(original, compressed)
      return "n/a" if original.zero?

      format("%.1f%% saved", 100.0 * (original - compressed) / original)
    end
  end
end
