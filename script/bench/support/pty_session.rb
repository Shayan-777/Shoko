# frozen_string_literal: true

require 'pty'
require 'io/console'

module ShokoBench
  # Drives one Shoko process on a real PTY and records every output chunk
  # with its arrival timestamp, so latency can be measured from a key write
  # to the moment the matching paint actually arrived (not when we polled).
  class PtySession
    ANSI_RE = /\e\[[0-9;?]*[A-Za-z]|\e\][^\a\e]*(?:\a|\e\\)?|\e[()][0-9A-Za-z=>]?/

    Chunk = Struct.new(:time, :data)

    attr_reader :pid

    def initialize(env, argv, rows:, cols:)
      @master, slave = PTY.open
      slave.winsize = [rows, cols]
      @chunks = []
      @mutex = Mutex.new
      @pid = Process.spawn(env, *argv, in: slave, out: slave, err: slave)
      slave.close
      @reader = Thread.new { pump }
    end

    # Opaque position marker: chunks recorded after this mark are "new".
    def mark
      @mutex.synchronize { @chunks.length }
    end

    def write(text)
      @master.write(text)
      monotonic_now
    end

    # Waits until the ANSI-stripped output that arrived after +since+
    # contains +pattern+ (String or Regexp). Returns the arrival time of the
    # first chunk that completed the match, or nil on timeout.
    def wait_for(pattern, since:, timeout:)
      deadline = monotonic_now + timeout
      loop do
        hit = match_arrival_time(pattern, since)
        return hit if hit
        return nil if monotonic_now >= deadline

        sleep(0.002)
      end
    end

    # Waits until at least +threshold+ bytes of raw output have arrived after
    # +since+; returns the arrival time of the chunk that crossed the
    # threshold, or nil on timeout. A coarse but robust "big repaint" signal.
    def wait_for_bytes(threshold, since:, timeout:)
      deadline = monotonic_now + timeout
      loop do
        hit = bytes_arrival_time(threshold, since)
        return hit if hit
        return nil if monotonic_now >= deadline

        sleep(0.002)
      end
    end

    # Waits until no new output has arrived for +quiet+ seconds (used to
    # detect "initial paint done"). Returns false if +timeout+ elapses first.
    def wait_for_quiet(quiet:, timeout:)
      deadline = monotonic_now + timeout
      loop do
        last = last_chunk_time
        now = monotonic_now
        return true if last && now - last >= quiet
        return false if now >= deadline

        sleep(0.01)
      end
    end

    def stripped_text(since: 0)
      raw = @mutex.synchronize { @chunks[since..].to_a.map(&:data).join }
      strip_ansi(raw)
    end

    # Largest gap (seconds) between consecutive chunk arrivals after +since+,
    # also counting the gap from the last chunk to +until_time+. This is the
    # "frozen spinner" metric: with a 10 Hz animation an unstarved UI keeps
    # this near 0.1 s.
    def max_paint_gap(since:, until_time:)
      times = @mutex.synchronize { @chunks[since..].to_a.map(&:time) }
      gaps = times.each_cons(2).map { |a, b| b - a }
      gaps << (until_time - times.last) unless times.empty?
      gaps.max || 0.0
    end

    def paint_gaps(since:)
      times = @mutex.synchronize { @chunks[since..].to_a.map(&:time) }
      times.each_cons(2).map { |a, b| b - a }
    end

    def alive?
      Process.waitpid(@pid, Process::WNOHANG).nil?
    rescue Errno::ECHILD
      false
    end

    def stop(graceful_key: nil, timeout: 5.0)
      write(graceful_key) if graceful_key && alive?
      deadline = monotonic_now + timeout
      sleep(0.05) while alive? && monotonic_now < deadline
      unless alive?
        finish_reader
        return
      end

      Process.kill('TERM', @pid)
      sleep(0.2)
      Process.kill('KILL', @pid) if alive?
      Process.waitpid(@pid)
    rescue Errno::ECHILD, Errno::ESRCH
      nil
    ensure
      finish_reader
    end

    private

    def pump
      loop do
        data = @master.readpartial(65_536)
        time = monotonic_now
        @mutex.synchronize { @chunks << Chunk.new(time, data) }
      end
    rescue EOFError, Errno::EIO, IOError
      nil
    end

    def finish_reader
      @reader&.join(1.0)
      @master.close unless @master.closed?
    rescue IOError
      nil
    end

    def bytes_arrival_time(threshold, since)
      chunks = @mutex.synchronize { @chunks[since..].to_a }
      total = 0
      chunks.each do |chunk|
        total += chunk.data.bytesize
        return chunk.time if total >= threshold
      end
      nil
    end

    def match_arrival_time(pattern, since)
      chunks = @mutex.synchronize { @chunks[since..].to_a }
      joined = +''
      chunks.each do |chunk|
        joined << chunk.data
        return chunk.time if matches?(strip_ansi(joined), pattern)
      end
      nil
    end

    def matches?(text, pattern)
      pattern.is_a?(Regexp) ? pattern.match?(text) : text.include?(pattern)
    end

    def last_chunk_time
      @mutex.synchronize { @chunks.last&.time }
    end

    def strip_ansi(text)
      text.gsub(ANSI_RE, '')
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
