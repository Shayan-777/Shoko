#!/usr/bin/env ruby
# frozen_string_literal: true

# Visual fidelity harness: drives bin/shoko on a PTY, interprets the ANSI
# stream into a screen grid, and dumps the page as plain text. Use it to
# eyeball formatting changes against the books in testbooks/.
#
#   ruby script/visual/capture_page.rb BOOK [keys] [cols] [rows]
#
# `keys` are sent after first paint (e.g. "ll" pages forward twice).
require 'pty'
require 'io/console'

book = ARGV[0]
keys = (ARGV[1] || '').chars # keys to send after first paint (e.g. pages forward)
cols = (ARGV[2] || 100).to_i
rows = (ARGV[3] || 34).to_i

require 'tmpdir'
env = {
  'HOME' => '/tmp/shoko-visual-home',
  'TERM' => 'xterm-256color',
}
require 'fileutils'
FileUtils.mkdir_p(env['HOME'])

buffer = +''
PTY.spawn(env, '/home/shayan/Shoko/bin/shoko', book.to_s) do |reader, writer, pid|
  reader.winsize = [rows, cols]
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + (ENV['SHOKO_CAPTURE_DEADLINE'] || 25).to_f
  sent_keys = false
  key_time = nil
  loop do
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    break if now > deadline

    if !sent_keys && buffer.length > 4000 && buffer.include?("\e[")
      sleep((ENV['SHOKO_CAPTURE_SETTLE'] || 2.5).to_f) # let it settle / paginate
      key_gap = (ENV['SHOKO_CAPTURE_KEY_GAP'] || 0.4).to_f
      keys.each { |k| writer.write(k); sleep key_gap }
      sent_keys = true
      key_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    break if sent_keys && key_time && now - key_time > 3.0

    ready = IO.select([reader], nil, nil, 0.3)
    next unless ready

    begin
      buffer << reader.read_nonblock(65_536)
    rescue IO::WaitReadable
      next
    rescue EOFError, Errno::EIO
      break
    end
  end
  writer.write('q') rescue nil
  sleep 0.4
  writer.write('q') rescue nil
  sleep 0.3
  begin
    Process.kill('TERM', pid)
  rescue StandardError
  end
end rescue nil

# Interpret the ANSI stream into a screen grid (minimal terminal emulation).
screen = Array.new(rows) { Array.new(cols, ' ') }
row = 0
col = 0
i = 0
s = buffer
while i < s.length
  ch = s[i]
  if ch == "\e"
    if s[i + 1] == '['
      j = i + 2
      j += 1 while j < s.length && s[j] =~ /[0-9;?]/
      final = s[j]
      params = s[(i + 2)...j]
      case final
      when 'H', 'f'
        parts = params.split(';')
        row = [[(parts[0] || '1').to_i - 1, 0].max, rows - 1].min
        col = [[(parts[1] || '1').to_i - 1, 0].max, cols - 1].min
      when 'J'
        screen = Array.new(rows) { Array.new(cols, ' ') } if params == '2' || params.empty?
      when 'K'
        (col...cols).each { |c| screen[row][c] = ' ' }
      when 'A' then row = [row - [params.to_i, 1].max, 0].max
      when 'B' then row = [row + [params.to_i, 1].max, rows - 1].min
      when 'C' then col = [col + [params.to_i, 1].max, cols - 1].min
      when 'D' then col = [col - [params.to_i, 1].max, 0].max
      end
      i = j + 1
      next
    elsif s[i + 1] == ']'
      j = s.index("\a", i) || s.index("\e\\", i) || (s.length - 1)
      i = j + 1
      next
    else
      i += 2
      next
    end
  elsif ch == "\r"
    col = 0
  elsif ch == "\n"
    row = [row + 1, rows - 1].min
    col = 0
  elsif ch == "\b"
    col = [col - 1, 0].max
  else
    if ch.ord >= 32
      screen[row][col] = ch if row < rows && col < cols
      col += 1
      if col >= cols
        col = 0
        row = [row + 1, rows - 1].min
      end
    end
  end
  i += 1
end

puts screen.map { |r| r.join.rstrip }.join("\n")
