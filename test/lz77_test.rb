# frozen_string_literal: true

require_relative "test_helper"

class LZ77Test < Minitest::Test
  # Expands tokens back into bytes, checking every back-reference is legal.
  def expand(tokens)
    out = String.new(encoding: Encoding::BINARY)
    tokens.each do |t|
      if t < 256
        out << t
      else
        len = t & 511
        dist = t >> 9
        assert_includes 3..258, len
        assert_includes 1..32_768, dist
        assert_operator dist, :<=, out.bytesize
        len.times { out << out.getbyte(out.bytesize - dist) }
      end
    end
    out
  end

  def tokenize(data, level, chunk: nil)
    m = Rdeflate::LZ77.new(level)
    tokens = []
    (chunk ? data.bytes.each_slice(chunk).map { |c| c.pack("C*") } : [data]).each do |piece|
      m.feed(piece)
      while (t = m.next_tokens(4096))
        tokens.concat(t[0])
      end
    end
    while (t = m.next_tokens(4096, final: true))
      tokens.concat(t[0])
    end
    tokens
  end

  def test_tokens_reproduce_input_at_every_level
    data = sample_inputs["mixed"] + sample_inputs["text"]
    (1..9).each { |level| assert_equal data, expand(tokenize(data, level)), "level #{level}" }
  end

  def test_incremental_feeding
    data = random_text(120_000)
    assert_equal data, expand(tokenize(data, 6, chunk: 997))
    assert_equal data, expand(tokenize(data, 2, chunk: 10_000))
  end

  def test_raw_slices_match_tokens
    data = random_text(50_000)
    m = Rdeflate::LZ77.new(6).feed(data)
    while (tokens, raw = m.next_tokens(1000, final: true))
      assert_equal raw, expand(tokens) if tokens.none? { |t| t >= 256 && (t >> 9) > 0 }
      assert_equal raw.bytesize, tokens.sum { |t| t < 256 ? 1 : t & 511 }
    end
  end

  def test_finds_maximum_length_matches
    tokens = tokenize("a" * 10_000, 6)
    assert_operator tokens.size, :<, 50
    assert(tokens.any? { |t| t >= 256 && (t & 511) == 258 })
  end

  def test_window_is_32k
    block = Random.new(1).bytes(1000)
    data = block + Random.new(2).bytes(40_000) + block
    tokens = tokenize(data, 9)
    assert(tokens.none? { |t| t >= 256 && (t >> 9) > 32_768 })
    assert_equal data, expand(tokens)
  end

  def test_history_trimming_keeps_output_valid
    # > TRIM_THRESHOLD so the window is rebased at least once.
    data = random_text(2_300_000, seed: 3)
    assert_equal data, Rdeflate.inflate(Rdeflate.deflate(data, level: 1))
  end

  def test_higher_levels_compress_better
    data = random_text(300_000)
    sizes = [1, 4, 6, 9].map { |l| Rdeflate.deflate(data, level: l).bytesize }
    assert_equal sizes.sort.reverse, sizes
  end

  def test_lazy_matching_beats_greedy
    # Classic lazy-matching win: "abcde" ... "bcdefgh" ... "abcdefgh".
    data = ("xabcdey" * 3 + "zbcdefghw" * 3 + "abcdefghq") * 50
    greedy = Rdeflate::LZ77.new(3)
    lazy = Rdeflate::LZ77.new(9)
    count = ->(m) { m.feed(data).next_tokens(1 << 20, final: true)[0].size }
    assert_operator count.call(lazy), :<=, count.call(greedy)
  end

  def test_invalid_level
    assert_raises(ArgumentError) { Rdeflate::LZ77.new(0) }
    assert_raises(ArgumentError) { Rdeflate::LZ77.new(10) }
  end
end
