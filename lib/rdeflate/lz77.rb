# frozen_string_literal: true

module Rdeflate
  # LZ77 match finder over a sliding 32 KiB window, modelled on zlib's
  # deflate_fast / deflate_slow: 3-byte hashes index singly linked hash
  # chains, the per-level configuration bounds how far chains are followed,
  # and levels 4-9 use lazy matching (a match is only taken if the match
  # starting at the next byte is not longer).
  #
  # Input is fed incrementally with #feed; #next_tokens returns tokens for
  # as much input as can be parsed without seeing more data.
  class LZ77
    WSIZE = 32_768
    WMASK = WSIZE - 1
    HASH_BITS = 15
    HASH_SIZE = 1 << HASH_BITS
    HASH_SHIFT = 32 - HASH_BITS
    MIN_MATCH = 3
    MAX_MATCH = 258
    # Bytes of lookahead kept in reserve so a match is never cut short just
    # because the caller has not fed the rest of the input yet.
    MIN_LOOKAHEAD = MAX_MATCH + MIN_MATCH + 1
    # A length-3 match further back than this is not worth its distance bits.
    TOO_FAR = 4096
    # Drop already-processed history once this much has accumulated.
    TRIM_THRESHOLD = 1 << 20

    Config = Struct.new(:good_length, :max_lazy, :nice_length, :max_chain, :lazy)

    # Same tuning table as zlib (good, lazy/insert, nice, chain).
    LEVELS = {
      1 => Config.new(4, 4, 8, 4, false),
      2 => Config.new(4, 5, 16, 8, false),
      3 => Config.new(4, 6, 32, 32, false),
      4 => Config.new(4, 4, 16, 16, true),
      5 => Config.new(8, 16, 32, 32, true),
      6 => Config.new(8, 16, 128, 128, true),
      7 => Config.new(8, 32, 128, 256, true),
      8 => Config.new(32, 128, 258, 1024, true),
      9 => Config.new(32, 258, 258, 4096, true)
    }.freeze

    attr_reader :config

    def initialize(level)
      @config = LEVELS.fetch(level) { raise ArgumentError, "LZ77 level must be 1..9, got #{level.inspect}" }
      @good = @config.good_length
      @max_lazy = @config.max_lazy
      @nice = @config.nice_length
      @max_chain = @config.max_chain
      @head = Array.new(HASH_SIZE, -1)
      @prev = Array.new(WSIZE, -1)
      @window = String.new(encoding: Encoding::BINARY)
      @pos = 0
    end

    def feed(data)
      @window << data.b
      self
    end

    # Bytes fed but not yet turned into tokens.
    def pending
      @window.bytesize - @pos
    end

    # Parses up to roughly +max_tokens+ tokens. Unless +final+, stops while
    # MIN_LOOKAHEAD bytes remain so matches can still grow into later input.
    # Returns [tokens, raw_bytes_covered] or nil if nothing could be parsed.
    def next_tokens(max_tokens, final: false)
      trim if @pos > TRIM_THRESHOLD
      limit = final ? @window.bytesize : @window.bytesize - MIN_LOOKAHEAD
      return nil if @pos >= limit

      start = @pos
      tokens = @config.lazy ? parse_lazy(limit, max_tokens) : parse_greedy(limit, max_tokens)
      [tokens, @window.byteslice(start, @pos - start)]
    end

    private

    def hash(w, p)
      ((((w.getbyte(p) << 16) | (w.getbyte(p + 1) << 8) | w.getbyte(p + 2)) * 0x9E37_79B1) >> HASH_SHIFT) & (HASH_SIZE - 1)
    end

    def insert(w, p)
      h = hash(w, p)
      cand = @head[h]
      @prev[p & WMASK] = cand
      @head[h] = p
      cand
    end

    # zlib's deflate_fast: take the first good match, and only index the
    # positions inside it when it is short.
    def parse_greedy(limit, max_tokens)
      w = @window
      size = w.bytesize
      pos = @pos
      tokens = []
      while pos < limit && tokens.size < max_tokens
        max_len = size - pos
        max_len = MAX_MATCH if max_len > MAX_MATCH
        len = 0
        if max_len >= MIN_MATCH
          cand = insert(w, pos)
          len, dist = longest_match(w, pos, cand, MIN_MATCH - 1, max_len) if cand >= 0 && cand > pos - WSIZE
        end
        if len >= MIN_MATCH && !(len == MIN_MATCH && dist > TOO_FAR)
          tokens << ((dist << 9) | len)
          if len <= @max_lazy
            stop = pos + len
            p = pos + 1
            while p < stop
              insert(w, p) if p + 2 < size
              p += 1
            end
          end
          pos += len
        else
          tokens << w.getbyte(pos)
          pos += 1
        end
      end
      @pos = pos
      tokens
    end

    # zlib's deflate_slow: hold each match back one byte to see whether the
    # next position offers something longer.
    def parse_lazy(limit, max_tokens)
      w = @window
      size = w.bytesize
      pos = @pos
      tokens = []
      prev_len = MIN_MATCH - 1
      prev_dist = 0
      pending = false # a literal/match starting at pos - 1 awaits a decision

      while pos < limit && tokens.size < max_tokens
        max_len = size - pos
        max_len = MAX_MATCH if max_len > MAX_MATCH
        cur_len = MIN_MATCH - 1
        cur_dist = 0
        if max_len >= MIN_MATCH
          cand = insert(w, pos)
          if cand >= 0 && cand > pos - WSIZE && prev_len < @max_lazy
            cur_len, cur_dist = longest_match(w, pos, cand, prev_len, max_len)
            cur_len = MIN_MATCH - 1 if cur_len == MIN_MATCH && cur_dist > TOO_FAR
          end
        end

        if prev_len >= MIN_MATCH && cur_len <= prev_len
          tokens << ((prev_dist << 9) | prev_len)
          stop = pos - 1 + prev_len
          p = pos + 1
          while p < stop
            insert(w, p) if p + 2 < size
            p += 1
          end
          pos = stop
          pending = false
          prev_len = MIN_MATCH - 1
        else
          tokens << w.getbyte(pos - 1) if pending
          pending = true
          prev_len = cur_len
          prev_dist = cur_dist
          pos += 1
        end
      end

      if pending
        if prev_len >= MIN_MATCH
          tokens << ((prev_dist << 9) | prev_len)
          stop = pos - 1 + prev_len
          p = pos
          while p < stop
            insert(w, p) if p + 2 < size
            p += 1
          end
          pos = stop
        else
          tokens << w.getbyte(pos - 1)
        end
      end
      @pos = pos
      tokens
    end

    # Walks the hash chain from +cand+ looking for a match longer than
    # +best_len+. Returns [length, distance] (length unchanged if nothing
    # better was found).
    def longest_match(w, cur, cand, best_len, max_len)
      chain = best_len >= @good ? @max_chain >> 2 : @max_chain
      nice = @nice < max_len ? @nice : max_len
      best_len = max_len if best_len > max_len
      best_dist = 0
      limit = cur - WSIZE
      prev = @prev
      while cand > limit && cand >= 0
        # Cheap rejection: the byte that would extend the best match so far.
        if w.getbyte(cand + best_len) == w.getbyte(cur + best_len) && w.getbyte(cand) == w.getbyte(cur)
          len = match_length(w, cand, cur, max_len)
          if len > best_len
            best_len = len
            best_dist = cur - cand
            break if len >= nice
          end
        end
        chain -= 1
        break if chain.zero?

        nxt = prev[cand & WMASK]
        break if nxt >= cand

        cand = nxt
      end
      [best_len, best_dist]
    end

    # Length of the common prefix of w[a, max] and w[b, max]. Short matches
    # are scanned byte by byte; long ones fall back to comparing substrings
    # (memcmp in C) with a binary search on the length.
    def match_length(w, a, b, max)
      len = 0
      while len < 16
        return len if len >= max || w.getbyte(a + len) != w.getbyte(b + len)

        len += 1
      end
      return max if w.byteslice(a, max) == w.byteslice(b, max)

      lo = len     # known equal
      hi = max - 1 # known: full length differs
      while lo < hi
        mid = (lo + hi + 1) >> 1
        if w.byteslice(a + lo, mid - lo) == w.byteslice(b + lo, mid - lo)
          lo = mid
        else
          hi = mid - 1
        end
      end
      lo
    end

    def trim
      delta = @pos - WSIZE
      @window = @window.byteslice(delta, @window.bytesize - delta)
      @head.map! { |v| v - delta }
      @prev.map! { |v| v - delta }
      @pos -= delta
    end
  end
end
