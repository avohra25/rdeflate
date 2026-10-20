# frozen_string_literal: true

require_relative "test_helper"

class InflateTest < Minitest::Test
  STRATEGIES = {
    "default" => Zlib::DEFAULT_STRATEGY,
    "filtered" => Zlib::FILTERED,
    "huffman only" => Zlib::HUFFMAN_ONLY,
    "rle" => Zlib::RLE,
    "fixed" => Zlib::FIXED
  }.freeze

  def test_inflates_zlib_output_at_every_level
    sample_inputs.each do |name, data|
      (0..9).each do |level|
        assert_equal data, Rdeflate.inflate(zlib_raw_deflate(data, level)), "#{name} level #{level}"
      end
    end
  end

  def test_inflates_zlib_output_for_every_strategy
    sample_inputs.each do |name, data|
      STRATEGIES.each do |sname, strategy|
        assert_equal data, Rdeflate.inflate(zlib_raw_deflate(data, 6, strategy)), "#{name} #{sname}"
      end
    end
  end

  def test_inflates_large_zlib_stream
    data = random_text(1_500_000)
    assert_equal data, Rdeflate.inflate(zlib_raw_deflate(data, 9))
    random = Random.new(5).bytes(1_200_000)
    assert_equal random, Rdeflate.inflate(zlib_raw_deflate(random, 6))
  end

  def test_flushes_produce_empty_stored_blocks
    data = random_text(40_000)
    z = Zlib::Deflate.new(6, -Zlib::MAX_WBITS)
    out = +""
    data.bytes.each_slice(3001).with_index do |chunk, i|
      out << z.deflate(chunk.pack("C*"), i.even? ? Zlib::SYNC_FLUSH : Zlib::FULL_FLUSH)
    end
    out << z.finish
    assert_equal data, Rdeflate.inflate(out)
  end

  def test_inflates_zlib_wrapped_body
    data = "abc" * 1000
    stream = Zlib::Deflate.deflate(data)
    inflater = Rdeflate::Inflater.new(stream, 2)
    assert_equal data, inflater.inflate
    assert_equal stream.bytesize - 4, inflater.end_pos # Adler-32 trailer follows
  end

  def test_hand_built_fixed_block
    stream = bits([1, 1], [1, 2], fixed_code(97), fixed_code(257), [0, 5], fixed_code(256))
    assert_equal "aaaa", Rdeflate.inflate(stream) # 'a' + (len 3, dist 1)
  end

  def test_hand_built_stored_block_and_end_pos
    stream = "\x01\x03\x00\xFC\xFFabcTRAILER".b
    inflater = Rdeflate::Inflater.new(stream)
    assert_equal "abc", inflater.inflate
    assert_equal 8, inflater.end_pos
  end

  def test_empty_final_fixed_block
    assert_equal "", Rdeflate.inflate("\x03\x00".b)
  end

  def test_result_is_binary
    assert_equal Encoding::BINARY, Rdeflate.inflate(zlib_raw_deflate("héllo")).encoding
  end

  # --- corrupt input ----------------------------------------------------

  def assert_data_error(stream, message = nil)
    err = assert_raises(Rdeflate::DataError) { Rdeflate.inflate(stream) }
    assert_match message, err.message if message
    err
  end

  def test_invalid_block_type
    assert_data_error "\x07".b, /block type/
  end

  def test_stored_length_mismatch
    assert_data_error "\x01\x05\x00\x00\x00hello".b, /stored block lengths/
  end

  def test_every_truncation_is_detected
    data = sample_inputs["mixed"]
    stream = zlib_raw_deflate(data)
    cuts = (0...stream.bytesize).step([stream.bytesize / 200, 1].max).to_a + [stream.bytesize - 1]
    cuts.each do |n|
      assert_raises(Rdeflate::TruncatedError, "cut at #{n}") { Rdeflate.inflate(stream.byteslice(0, n)) }
    end
  end

  def test_distance_too_far_back
    assert_data_error bits([1, 1], [1, 2], fixed_code(257), [0, 5], fixed_code(256)), /too far back/
    assert_data_error bits([1, 1], [1, 2], fixed_code(97), fixed_code(257), [Rdeflate::Huffman.reverse(1, 5), 5]),
                      /too far back/
  end

  def test_invalid_fixed_symbols
    assert_data_error bits([1, 1], [1, 2], fixed_code(286)), /literal\/length/
    assert_data_error bits([1, 1], [1, 2], fixed_code(287)), /literal\/length/
    assert_data_error bits([1, 1], [1, 2], fixed_code(97), fixed_code(257), [Rdeflate::Huffman.reverse(30, 5), 5]),
                      /distance code/
  end

  def test_too_many_length_symbols
    assert_data_error bits([1, 1], [2, 2], [30, 5], [0, 5], [0, 4]), /too many length/
  end

  def test_oversubscribed_code_length_code
    assert_data_error bits([1, 1], [2, 2], [0, 5], [0, 5], [0, 4], [1, 3], [1, 3], [1, 3], [1, 3]), /over-subscribed/
  end

  def test_repeat_without_previous_length
    # Code length code: symbols 16 and 0 get length 1 (0 -> "0", 16 -> "1").
    header = [[1, 1], [2, 2], [0, 5], [0, 5], [0, 4], [1, 3], [0, 3], [0, 3], [1, 3]]
    assert_data_error bits(*header, [1, 1], [0, 2]), /no previous length/
  end

  def test_too_many_code_lengths_and_missing_end_of_block
    # Code length code: symbols 18 and 0 get length 1 (0 -> "0", 18 -> "1").
    header = [[1, 1], [2, 2], [0, 5], [0, 5], [0, 4], [0, 3], [0, 3], [1, 3], [1, 3]]
    assert_data_error bits(*header, [1, 1], [127, 7], [1, 1], [127, 7]), /too many code lengths/
    assert_data_error bits(*header, [1, 1], [127, 7], [1, 1], [109, 7]), /end-of-block/
  end

  def test_random_garbage_only_raises_rdeflate_errors
    rng = Random.new(99)
    300.times do
      garbage = rng.bytes(rng.rand(1..200))
      begin
        Rdeflate.inflate(garbage)
      rescue Rdeflate::DataError
        # expected for almost all inputs
      end
    end
  end

  # Flip bytes in valid streams and check we accept/reject exactly what
  # zlib accepts/rejects, with identical output when accepted.
  def test_mutations_agree_with_zlib
    rng = Random.new(2024)
    sources = [sample_inputs["text"], sample_inputs["mixed"], sample_inputs["short period"], "Hello, Hello, Hello!" * 3]
    streams = sources.flat_map { |d| [zlib_raw_deflate(d, 1), zlib_raw_deflate(d, 9), zlib_raw_deflate(d, 6, Zlib::FIXED)] }
    400.times do |i|
      s = streams[i % streams.size].dup
      rng.rand(1..3).times { s.setbyte(rng.rand(s.bytesize), rng.rand(256)) }
      expected = begin
        zlib_raw_inflate(s)
      rescue Zlib::Error
        :error
      end
      actual = begin
        Rdeflate.inflate(s)
      rescue Rdeflate::DataError
        :error
      end
      assert expected == actual, "mutation #{i}: zlib #{expected == :error ? "rejected" : "accepted"}, rdeflate disagreed"
    end
  end
end
