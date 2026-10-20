# rdeflate

DEFLATE ([RFC 1951](https://www.rfc-editor.org/rfc/rfc1951)), zlib
([RFC 1950](https://www.rfc-editor.org/rfc/rfc1950)) and gzip
([RFC 1952](https://www.rfc-editor.org/rfc/rfc1952)) in pure Ruby: no C
extension, no dependencies beyond the standard library. Everything it writes
inflates with `Zlib`, and everything `Zlib` writes inflates with it; the test
suite checks both directions on every compression level.

It is not trying to replace `Zlib` (which is 30-40x faster, see below). It is
a readable, tested reference for how DEFLATE actually works, small enough to
read in an afternoon (about 1,300 lines of library code, not counting comments).

## Features

- **Inflater** for stored, fixed-Huffman and dynamic-Huffman blocks, with
  zlib-compatible validation of corrupt input: over-subscribed or incomplete
  codes, missing end-of-block, distances too far back, bad stored lengths,
  truncation. A fuzz test flips bytes in valid streams and checks rdeflate
  accepts and rejects exactly the same inputs as zlib.
- **Compressor** with LZ77 over a 32 KiB window (3-byte hash chains), zlib's
  per-level tuning table, greedy matching for levels 1-3 and lazy matching
  for 4-9, length-limited canonical Huffman codes (15 bits, 7 for the code
  length code), and an exact per-block cost comparison between stored, fixed
  and dynamic encodings.
- **Adler-32 and CRC-32**, incremental like `Zlib.adler32` / `Zlib.crc32`.
- **zlib container** with the standard header levels (`78 01`, `78 5E`,
  `78 9C`, `78 DA`) and Adler-32 trailer.
- **gzip container**: file name, comment, mtime, OS, extra field, text flag
  and header CRC (FHCRC), multi-member files, trailing zero padding.
- **Streaming**: `Deflater#deflate` emits finished blocks as input arrives;
  `GzipWriter` wraps any IO (`write`, `<<`, `puts`, `print`).
- **CLI**: `bin/rdeflate compress | decompress | info` in gzip, zlib or raw
  mode.

## Usage

```ruby
require "rdeflate"

gz = Rdeflate.gzip(data, level: 9, filename: "notes.txt", mtime: Time.now)
Rdeflate.gunzip(gz)                      # concatenates all members

z = Rdeflate.zlib_compress(data)         # same bytes Zlib::Inflate.inflate expects
Rdeflate.zlib_decompress(z)

raw = Rdeflate.deflate(data, level: 1)   # headerless DEFLATE
Rdeflate.inflate(raw)

Rdeflate.compress(data, format: :zlib)   # :gzip (default), :zlib, :raw
Rdeflate.decompress(bytes)               # detects gzip / zlib / raw

# Header fields of every member
Rdeflate::GzipFormat.members(gz).each do |m|
  puts [m.filename, Time.at(m.mtime), m.data.bytesize].inspect
end

# Streaming
Rdeflate::GzipWriter.open("log.gz", level: 6) do |gz|
  1000.times { |i| gz.puts "event #{i}" }
end
Rdeflate::GzipReader.open("log.gz") { |r| r.each_line.first(3) }

d = Rdeflate::Deflater.new(level: 6)
File.open("big.deflate", "wb") do |out|
  File.open("big.bin", "rb") { |f| out.write(d.deflate(f.read(1 << 16))) until f.eof? }
  out.write(d.finish)
end
```

Errors are all subclasses of `Rdeflate::Error`: `DataError` for malformed
data, with `TruncatedError` (input ended early) and `ChecksumError` (Adler-32,
CRC-32, length or header CRC mismatch) beneath it.

### Command line

```text
$ bin/rdeflate compress -9 -v notes.txt
notes.txt: 12990 -> 5445 bytes (58.1% saved) -> notes.txt.gz
$ bin/rdeflate info notes.txt.gz
notes.txt.gz: gzip
  member 1: 5445 -> 12990 bytes (58.1% saved) name="notes.txt" mtime=2026-10-20T16:13:49Z os=3
$ bin/rdeflate decompress notes.txt.gz          # writes notes.txt
$ bin/rdeflate compress --zlib -c < in > in.zz   # stdin/stdout
$ bin/rdeflate decompress --format raw -c in.deflate
```

Options: `-0`..`-9` / `--level N`, `--gzip` `--zlib` `--raw` / `--format`
(decompress also accepts `auto`, the default), `-c` (stdout), `-o PATH`,
`-n` (don't store name/mtime), `-f` (overwrite), `-v`. Input files are never
deleted.

## Design notes

**Bit I/O.** DEFLATE packs fields LSB first but Huffman codes MSB first.
`BitReader` keeps up to a few bytes in an Integer bit buffer; decoding peeks
`max_length` bits and looks them up in a table indexed by the *bit-reversed*
code, so one array lookup yields `(symbol << 4) | length`. Tables are sized
to the longest code actually present, so a typical dynamic block builds a
512-4096 entry table rather than 32K. At the end of a stream, `align` hands
any whole bytes left in the bit buffer back to the byte stream, which is how
the zlib and gzip parsers find their trailers.

**Back-references** are applied with string operations rather than byte
loops: a non-overlapping copy is one `byteslice`, and an overlapping one
(distance < length, e.g. run-length encoding with distance 1) repeats the
last `distance` bytes with `String#*`. This is most of why inflating is ~10
MB/s in plain interpreted Ruby.

**Validation mirrors zlib.** Over-subscribed codes are always rejected;
incomplete codes are rejected except the single one-bit code zlib also
allows; an all-zero distance code is legal until a distance is actually
used. Symbols 286/287 and distance codes 30/31 are errors. That is what lets
the mutation test demand exact agreement with zlib.

**LZ77.** `LZ77` mirrors zlib's `deflate_fast` and `deflate_slow`: positions
are indexed by a multiplicative hash of the next three bytes into `head`
(newest position per hash) and `prev` (a 32K ring of chain links). Match
length is first compared byte by byte; past 16 bytes it compares whole
substrings (a `memcmp` in C) and binary-searches the mismatch, which keeps
long runs cheap. Lazy matching holds each match back one byte to see if the
next position gives a longer one. Matches of length 3 more than 4 KiB back
are dropped, as in zlib. Input is fed incrementally; parsing stops 262 bytes
short of the end until `finish`, and processed history is trimmed (and the
hash tables rebased) once it passes 1 MiB, so memory stays bounded.

**Huffman construction.** Code lengths come from a two-queue Huffman build
over the sorted frequencies. If the tree is deeper than the limit, the
per-length counts are repaired the way zlib/miniz do it (move overflowing
leaves to the limit, then repeatedly split a shorter leaf until the Kraft sum
is exactly 1) and lengths are re-dealt so frequent symbols get the short
codes. Single-symbol alphabets are padded to two codes, so every code
rdeflate emits is complete.

**Block choice.** Tokens are buffered in blocks of 16K symbols. For each
block the encoder computes the exact bit cost of a stored block (including
alignment padding), the fixed code, and the dynamic code (including its
run-length-encoded header with symbols 16/17/18) and writes the cheapest.
Random data therefore comes out as stored blocks (+0.03%), short inputs as
fixed blocks, and text as dynamic blocks.

## Benchmarks

Measured with `rake bench` (`benchmarks/bench.rb`) on this project's dev box:
Ruby 3.3.8 without YJIT, zlib 1.3.1, an Intel Xeon VM, single thread. Each
corpus is 1 MiB: the first MiB of Ruby's own stdlib sources, the first MiB of
`libruby.so`, a synthetic web access log, and random bytes. Sizes are
compressed size as a percentage of the input (lower is better); speeds are
input MB/s (best of several runs).

| Corpus | Level | rdeflate size | zlib size | rdeflate compress | zlib compress | rdeflate inflate | zlib inflate |
|---|---:|---:|---:|---:|---:|---:|---:|
| Ruby source | 1 | 30.14% | 30.59% | 2.80 MB/s | 102.15 MB/s | 8.66 MB/s | 246.24 MB/s |
| Ruby source | 6 | 24.68% | 24.70% | 0.90 MB/s | 34.26 MB/s | 11.03 MB/s | 277.81 MB/s |
| Ruby source | 9 | 24.52% | 24.53% | 0.19 MB/s | 9.09 MB/s | 11.48 MB/s | 258.03 MB/s |
| libruby.so | 1 | 46.43% | 46.57% | 1.91 MB/s | 71.52 MB/s | 5.86 MB/s | 186.40 MB/s |
| libruby.so | 6 | 42.77% | 42.79% | 0.58 MB/s | 20.94 MB/s | 6.54 MB/s | 178.67 MB/s |
| libruby.so | 9 | 42.60% | 42.60% | 0.12 MB/s | 6.08 MB/s | 7.01 MB/s | 195.87 MB/s |
| access log | 1 | 25.95% | 26.36% | 3.04 MB/s | 158.04 MB/s | 11.17 MB/s | 360.09 MB/s |
| access log | 6 | 20.77% | 20.78% | 0.95 MB/s | 41.49 MB/s | 14.29 MB/s | 311.22 MB/s |
| access log | 9 | 20.08% | 20.09% | 0.19 MB/s | 15.90 MB/s | 14.19 MB/s | 381.26 MB/s |
| random | 1 | 100.03% | 100.03% | 1.72 MB/s | 56.41 MB/s | 2653.94 MB/s | 4503.53 MB/s |
| random | 6 | 100.03% | 100.03% | 1.60 MB/s | 51.41 MB/s | 1291.19 MB/s | 3481.34 MB/s |
| random | 9 | 100.03% | 100.03% | 1.58 MB/s | 53.00 MB/s | 2440.12 MB/s | 3342.19 MB/s |

Takeaways: compression ratio matches zlib to within 0.02 points at levels 6
and 9 and is slightly better at level 1 (zlib 1.3's level 1 uses a cheaper
hash). Pure Ruby is roughly 30-50x slower than C zlib at compressing and
20-30x slower at inflating; stored (random) data is a couple of `byteslice`
calls per 64 KiB block, so it inflates at memory speed in both.

## Tests

92 tests (Minitest), run with either of:

```sh
rake test
ruby -Ilib -Itest -e 'Dir.glob("test/**/*_test.rb").sort.each { |f| require File.expand_path(f) }'
```

They cover: checksums against `Zlib.adler32`/`Zlib.crc32`; bit I/O; Huffman
construction (optimality against a reference, the 15- and 7-bit limits on
Fibonacci weights); every compression level in both directions against
`Zlib` on empty, 1-byte, all-256-bytes, highly repetitive, max-length-match,
random and >1 MB inputs; all five zlib strategies; sync/full flush points;
hand-built corrupt streams for each error path; every truncation point;
byte-flip mutations compared with zlib's verdict; zlib/gzip headers and
trailers, multi-member files, header CRC; streaming; and the CLI.

## Layout

```text
lib/rdeflate.rb               top-level API
lib/rdeflate/bit_reader.rb    LSB-first bit input, Huffman decode step
lib/rdeflate/bit_writer.rb    LSB-first bit output
lib/rdeflate/huffman.rb       canonical codes, decoder tables, length-limited construction
lib/rdeflate/inflater.rb      RFC 1951 decoder
lib/rdeflate/lz77.rb          hash-chain match finder, greedy + lazy parsing
lib/rdeflate/block_encoder.rb stored/fixed/dynamic block writer and cost model
lib/rdeflate/deflater.rb      streaming compressor
lib/rdeflate/zlib_format.rb   RFC 1950 container
lib/rdeflate/gzip_format.rb   RFC 1952 container
lib/rdeflate/stream.rb        GzipWriter / GzipReader
lib/rdeflate/cli.rb           command-line interface (bin/rdeflate)
benchmarks/bench.rb           comparison with Zlib
```

## License

MIT, see [LICENSE](LICENSE).
