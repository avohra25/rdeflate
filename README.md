# rdeflate

DEFLATE (RFC 1951), zlib (RFC 1950) and gzip (RFC 1952) in pure Ruby, with no
dependencies beyond the standard library.

Work in progress. Currently implemented:

- LSB-first bit reader and writer
- Adler-32 and CRC-32
- A complete inflater: stored, fixed-Huffman and dynamic-Huffman blocks, with
  strict validation of corrupt input (`Rdeflate::DataError`,
  `Rdeflate::TruncatedError`)

```ruby
require "rdeflate"
Rdeflate.inflate(raw_deflate_bytes)
```

Tests cross-check against Ruby's bundled `Zlib`:

```sh
rake test
# or, without rake/bundler:
ruby -Ilib -Itest -e 'Dir.glob("test/**/*_test.rb").sort.each { |f| require File.expand_path(f) }'
```

## License

MIT
