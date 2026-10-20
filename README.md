# rdeflate

DEFLATE (RFC 1951), zlib (RFC 1950) and gzip (RFC 1952) in pure Ruby, with no
dependencies beyond the standard library. Output is interoperable with
`Zlib` in both directions.

- Inflater for stored, fixed-Huffman and dynamic-Huffman blocks with strict
  validation of corrupt input
- Compressor with LZ77 hash chains, lazy matching and zlib-style levels 0-9,
  length-limited (15-bit) canonical Huffman codes, and a per-block choice of
  stored / fixed / dynamic encoding
- Adler-32 and CRC-32
- zlib and gzip containers (file name, comment, mtime, extra field, header
  CRC, multi-member files)
- Streaming `Deflater` and an IO-friendly `GzipWriter`
- `rdeflate` command-line tool

## Usage

```ruby
require "rdeflate"

Rdeflate.gzip(data, level: 9, filename: "notes.txt")   # gzip member
Rdeflate.gunzip(gz)                                     # all members
Rdeflate.zlib_compress(data) / Rdeflate.zlib_decompress(z)
Rdeflate.deflate(data, level: 1) / Rdeflate.inflate(raw)
Rdeflate.decompress(bytes)                              # auto-detects the container
```

```sh
bin/rdeflate compress -9 notes.txt          # writes notes.txt.gz
bin/rdeflate decompress notes.txt.gz        # writes notes.txt
bin/rdeflate compress --zlib -c < in > out  # stdin -> stdout
bin/rdeflate info notes.txt.gz
```

## Tests

```sh
rake test
# or, without rake/bundler:
ruby -Ilib -Itest -e 'Dir.glob("test/**/*_test.rb").sort.each { |f| require File.expand_path(f) }'
```

## License

MIT
