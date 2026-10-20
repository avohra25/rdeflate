# frozen_string_literal: true

require_relative "lib/rdeflate/version"

Gem::Specification.new do |spec|
  spec.name = "rdeflate"
  spec.version = Rdeflate::VERSION
  spec.authors = ["avohra25"]
  spec.email = ["182703837+avohra25@users.noreply.github.com"]

  spec.summary = "DEFLATE, zlib and gzip in pure Ruby"
  spec.description = "A dependency-free implementation of DEFLATE (RFC 1951) with LZ77 hash chains, " \
                     "lazy matching and length-limited Huffman coding, plus the zlib (RFC 1950) and " \
                     "gzip (RFC 1952) containers. Output is interoperable with Zlib in both directions."
  spec.homepage = "https://github.com/avohra25/rdeflate"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "bin/*", "README.md", "LICENSE"]
  spec.bindir = "bin"
  spec.executables = Dir["bin/*"].map { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
