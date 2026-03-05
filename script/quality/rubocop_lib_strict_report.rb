#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'pathname'
require 'tempfile'
require 'time'
require 'yaml'

module RuboCopLibStrictReport
  module_function

  ROOT = Pathname.new(File.expand_path('../..', __dir__))
  DEFAULT_OUTPUT_PATH = ROOT.join('tmp', 'reports', 'rubocop_lib_strict_report.json')
  TARGET_GLOB = 'lib/shoko'

  def run!
    output_path = Pathname.new(ARGV[0] || DEFAULT_OUTPUT_PATH)
    output_path.dirname.mkpath

    Tempfile.create(%w[rubocop-strict .yml], ROOT.to_s) do |config_file|
      config_file.write(strict_config_yaml)
      config_file.flush

      stdout, stderr, status = Open3.capture3(*rubocop_command(config_file.path))
      ensure_rubocop_executed!(status, stderr)

      rubocop_payload = JSON.parse(stdout)
      report_payload = build_report_payload(rubocop_payload)
      File.write(output_path, JSON.pretty_generate(report_payload))
      print_summary(report_payload, output_path)
    end
  end

  def strict_config_yaml
    raw_config = YAML.safe_load(
      ROOT.join('.rubocop.yml').read,
      aliases: true,
      permitted_classes: [Regexp, Symbol]
    )
    strict_config = raw_config.reject { |key, _value| key == 'inherit_from' }
    YAML.dump(strict_config)
  end

  def rubocop_command(config_path)
    [
      'bundle',
      'exec',
      'rubocop',
      TARGET_GLOB,
      '--config',
      config_path,
      '--format',
      'json',
    ]
  end

  def ensure_rubocop_executed!(status, stderr)
    return if status.success? || status.exitstatus == 1

    raise "RuboCop failed to execute (exit #{status.exitstatus}): #{stderr}"
  end

  def build_report_payload(rubocop_payload)
    files = rubocop_payload.fetch('files')
    summary = rubocop_payload.fetch('summary')

    offenses_by_cop = Hash.new(0)
    offenses_by_file = []

    files.each do |file|
      offense_count = file.fetch('offenses').length
      offenses_by_file << { 'path' => file.fetch('path'), 'count' => offense_count } if offense_count.positive?
      file.fetch('offenses').each do |offense|
        offenses_by_cop[offense.fetch('cop_name')] += 1
      end
    end

    {
      'generated_at' => Time.now.utc.iso8601,
      'scope' => TARGET_GLOB,
      'strict_config' => '.rubocop.yml without inherit_from',
      'summary' => {
        'inspected_file_count' => summary.fetch('inspected_file_count'),
        'offense_count' => summary.fetch('offense_count'),
        'target_file_count' => files.length,
        'files_with_offenses' => offenses_by_file.length,
      },
      'offenses_by_cop' => sort_counts(offenses_by_cop),
      'offenses_by_file' => offenses_by_file.sort_by { |entry| [-entry.fetch('count'), entry.fetch('path')] },
    }
  end

  def sort_counts(count_hash)
    count_hash.map do |name, count|
      { 'name' => name, 'count' => count }
    end.sort_by { |entry| [-entry.fetch('count'), entry.fetch('name')] }
  end

  def print_summary(report_payload, output_path)
    summary = report_payload.fetch('summary')

    puts 'RuboCop strict report generated'
    puts "output: #{output_path}"
    puts "scope: #{report_payload.fetch('scope')}"
    puts "inspected: #{summary.fetch('inspected_file_count')}"
    puts "offenses: #{summary.fetch('offense_count')}"
    puts "files_with_offenses: #{summary.fetch('files_with_offenses')}"
    puts 'top_cops:'
    report_payload.fetch('offenses_by_cop').first(10).each do |entry|
      puts "  #{entry.fetch('name')}: #{entry.fetch('count')}"
    end
    puts 'top_files:'
    report_payload.fetch('offenses_by_file').first(10).each do |entry|
      puts "  #{entry.fetch('path')}: #{entry.fetch('count')}"
    end
  end
end

RuboCopLibStrictReport.run!
