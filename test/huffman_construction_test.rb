# frozen_string_literal: true

require_relative "test_helper"

class HuffmanConstructionTest < Minitest::Test
  H = Rdeflate::Huffman

  def kraft(lengths, max)
    lengths.sum { |l| l.zero? ? 0 : 1 << (max - l) }
  end

  def cost(freqs, lengths)
    freqs.each_index.sum { |i| freqs[i] * lengths[i] }
  end

  # Reference: plain (unlimited) Huffman cost via a sorted merge.
  def huffman_cost(freqs)
    w = freqs.select(&:positive?).sort
    total = 0
    while w.size > 1
      a = w.shift
      b = w.shift
      total += a + b
      w.insert(w.bsearch_index { |x| x >= a + b } || w.size, a + b)
    end
    total
  end

  def test_complete_and_optimal
    rng = Random.new(11)
    200.times do
      freqs = Array.new(rng.rand(2..286)) { rng.rand < 0.3 ? 0 : rng.rand(1..1000) }
      freqs[rng.rand(freqs.size)] = 5
      freqs[(freqs.index(5) + 1) % freqs.size] = 7 if freqs.count(&:positive?) < 2
      optimal = huffman_cost(freqs)
      unlimited = H.lengths_from_frequencies(freqs, 64)
      assert_equal optimal, cost(freqs, unlimited)
      lengths = H.lengths_from_frequencies(freqs, 15)
      assert_equal 1 << 15, kraft(lengths, 15)
      if unlimited.max <= 15
        assert_equal optimal, cost(freqs, lengths)
      else # the limit binds: slightly worse than optimal, never better
        assert_operator cost(freqs, lengths), :>=, optimal
        assert_operator cost(freqs, lengths), :<=, optimal * 1.01
      end
      freqs.each_index { |i| assert_equal freqs[i].zero?, lengths[i].zero? }
    end
  end

  def test_length_limit_enforced_on_fibonacci_weights
    fib = [1, 1]
    fib << fib[-1] + fib[-2] while fib.size < 30
    [15, 7, 5].each do |limit|
      freqs = fib.first(limit == 15 ? 30 : 19)
      lengths = H.lengths_from_frequencies(freqs, limit)
      assert_operator lengths.max, :<=, limit
      assert_equal 1 << limit, kraft(lengths, limit), "limit #{limit} must stay complete"
      # More frequent symbols never get longer codes.
      order = freqs.each_index.sort_by { |i| -freqs[i] }
      order.each_cons(2) { |a, b| assert_operator lengths[a], :<=, lengths[b] }
    end
  end

  def test_degenerate_inputs_give_two_codes
    assert_equal [1, 1, 0], H.lengths_from_frequencies([0, 0, 0], 15)
    assert_equal [1, 1, 0, 0], H.lengths_from_frequencies([0, 9, 0, 0], 15)
    assert_equal [1, 1], H.lengths_from_frequencies([3, 0], 15)
  end

  def test_constructed_codes_decode
    rng = Random.new(5)
    freqs = Array.new(286) { rng.rand(0..50) }
    lengths = H.lengths_from_frequencies(freqs, 15)
    codes = H.encoder_codes(lengths)
    syms = Array.new(2000) { s = rng.rand(286); lengths[s].zero? ? 256 : s }
    stream = bits(*syms.map { |s| [codes[s], lengths[s]] })
    dec = H::Decoder.new(lengths)
    r = Rdeflate::BitReader.new(stream)
    syms.each { |s| assert_equal s, r.decode(dec) }
  end
end
