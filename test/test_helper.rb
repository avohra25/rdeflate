# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "zlib"
require "stringio"
require "rdeflate"

module TestHelper
  # Deterministic, varied inputs covering the usual edge cases.
  def sample_inputs(seed: 1234)
    rng = Random.new(seed)
    words = %w[the quick brown fox jumps over lazy dog deflate huffman window match literal stream]
    {
      "empty" => "".b,
      "one byte" => "x".b,
      "two bytes" => "\x00\xFF".b,
      "all 256 bytes" => (0..255).to_a.pack("C*"),
      "all bytes x4 shuffled" => (0..255).to_a.*(4).shuffle(random: rng).pack("C*"),
      "run of zeros" => ("\0" * 100_000).b,
      "short period" => ("abc" * 20_000).b,
      "long period" => (rng.bytes(300) * 400).b,
      "random 64k" => rng.bytes(65_536),
      "random 70000" => rng.bytes(70_000), # crosses a stored-block boundary
      "text" => Array.new(20_000) { words.sample(random: rng) }.join(" ").b,
      "mixed" => (rng.bytes(5000) + ("hello world " * 2000) + rng.bytes(5000) + ("\x01" * 3000)).b,
      "skewed" => Array.new(50_000) { rng.rand < 0.97 ? "a" : (rng.rand(256)).chr }.join.b,
      "max-length matches" => (("q" * 258) + "Z").*(300).b
    }
  end

  def random_text(bytes, seed: 7)
    rng = Random.new(seed)
    vocab = Array.new(2000) { Array.new(rng.rand(2..10)) { (97 + rng.rand(26)).chr }.join }
    out = +""
    out << vocab[(rng.rand**3 * vocab.size).floor] << (rng.rand < 0.1 ? "\n" : " ") while out.bytesize < bytes
    out.byteslice(0, bytes).b
  end

  def zlib_raw_deflate(data, level = Zlib::DEFAULT_COMPRESSION, strategy = Zlib::DEFAULT_STRATEGY)
    z = Zlib::Deflate.new(level, -Zlib::MAX_WBITS, Zlib::DEF_MEM_LEVEL, strategy)
    out = z.deflate(data, Zlib::FINISH)
    z.close
    out
  end

  def zlib_raw_inflate(data)
    z = Zlib::Inflate.new(-Zlib::MAX_WBITS)
    out = z.inflate(data)
    z.finish
    z.close
    out
  end

  # Builds a raw stream from bit fields: [[value, nbits], ...].
  def bits(*fields)
    w = Rdeflate::BitWriter.new
    fields.each { |value, n| w.write_bits(value, n) }
    w.align
    w.string
  end

  # The fixed-Huffman code for a literal/length symbol, as [reversed, length].
  def fixed_code(sym)
    lengths = Rdeflate::Tables::FIXED_LITLEN_LENGTHS
    code = Rdeflate::Huffman.canonical_codes(lengths)[sym]
    [Rdeflate::Huffman.reverse(code, lengths[sym]), lengths[sym]]
  end
end

Minitest::Test.include(TestHelper)
