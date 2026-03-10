#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require 'pty'
require 'rbconfig'

module ShokoStartupMenuBenchmark
  module_function

  ANSI_ESCAPE = /\e\[[0-9;?]*[A-Za-z]/.freeze

  def run(argv = ARGV)
    options = parse_options(argv)
    puts "Shoko startup benchmark (menu first paint)"
    puts "Ruby: #{RUBY_VERSION}"
    puts "Iterations: #{options[:iterations]} (warmup: #{options[:warmup]})"
    puts

    options[:warmup].times { run_once }
    samples = Array.new(options[:iterations]) { run_once }

    print_stats(samples)
  end

  def parse_options(argv)
    options = { iterations: 20, warmup: 2 }
    OptionParser.new do |opts|
      opts.banner = 'Usage: startup_menu_benchmark.rb [options]'
      opts.on('-n', '--iterations N', Integer, 'Number of measured runs (default: 20)') do |value|
        options[:iterations] = [value.to_i, 1].max
      end
      opts.on('-w', '--warmup N', Integer, 'Number of warmup runs (default: 2)') do |value|
        options[:warmup] = [value.to_i, 0].max
      end
    end.parse!(argv)
    options
  end

  def run_once
    output = +''
    PTY.spawn(RbConfig.ruby, '-e', child_script) do |reader, _writer, _pid|
      begin
        loop { output << reader.readpartial(4096) }
      rescue EOFError, Errno::EIO
      end
    end

    clean_output = output.gsub(ANSI_ESCAPE, '')
    json_line = clean_output.lines.reverse.find { |line| line.include?('"total_ms"') }
    raise 'benchmark run did not produce metrics output' unless json_line

    JSON.parse(json_line, symbolize_names: true)
  end

  def child_script
    root = File.expand_path('../..', __dir__)
    <<~RUBY
      require 'json'
      system('stty rows 40 cols 120')

      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      $LOAD_PATH.unshift File.expand_path('lib', #{root.dump})
      require 'shoko'
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      module Shoko
        module Adapters::Input::Controllers
          module Menu
            class Controller
              alias __startup_bench_orig_main_loop main_loop unless method_defined?(:__startup_bench_orig_main_loop)
              def main_loop
                draw_screen
              end
            end
          end
        end
      end

      run_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Shoko::Composition::ContainerFactory.build_unified_application(epub_path: nil, log_config: {}).run
      run_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      puts({
        require_ms: ((t1 - t0) * 1000.0),
        run_ms: ((run_end - run_start) * 1000.0),
        total_ms: ((run_end - t0) * 1000.0)
      }.to_json)
    RUBY
  end

  def print_stats(samples)
    %i[require_ms run_ms total_ms].each do |metric|
      values = samples.map { |sample| sample.fetch(metric).to_f }.sort
      mean = values.sum / values.length
      median = percentile(values, 50)
      p95 = percentile(values, 95)
      min = values.first
      max = values.last
      puts format('%-10s mean=%7.2f  median=%7.2f  p95=%7.2f  min=%7.2f  max=%7.2f',
                  metric, mean, median, p95, min, max)
    end
  end

  def percentile(sorted_values, percentile_rank)
    return sorted_values.first if sorted_values.length == 1

    idx = ((percentile_rank / 100.0) * (sorted_values.length - 1)).round
    sorted_values[idx]
  end
end

ShokoStartupMenuBenchmark.run if $PROGRAM_NAME == __FILE__
