# frozen_string_literal: true

require 'spec_helper'
require 'ripper'

RSpec.describe 'Failure-boundary policy' do
  let(:lib_root) { File.expand_path('../../../lib/shoko', __dir__) }
  let(:files) { Dir[File.join(lib_root, '**', '*.rb')].sort }

  it 'parses every scanned source and forbids process-wide exception catches' do
    offenders = []
    files.each do |path|
      source = File.read(path)
      raise "Architecture scan could not parse #{path}" unless Ripper.sexp(source)

      source.lines.each_with_index do |line, index|
        offenders << "#{path}:#{index + 1}" if line.match?(/\brescue\s+(?:Exception|Object|BasicObject)\b/)
      end
    end
    expect(offenders).to be_empty, "Overbroad rescue clauses:\n#{offenders.join("\n")}"
  end

  it 'requires each StandardError branch to mark containment or delegate an explicit failure policy' do
    offenders = []
    files.each do |path|
      lines = File.readlines(path)
      lines.each_with_index do |line, index|
        next unless line.match?(/\brescue StandardError\b/)

        marker = lines[[index - 2, 0].max...index].any? { |candidate| candidate.include?('# resilient-boundary') }
        branch = lines[index, 7].join
        explicit_policy = branch.match?(/^\s*(?:raise(?:\s|$)|(?:raise|handle|swallow|report)_\w+\()/)
        offenders << "#{path}:#{index + 1}" unless marker || explicit_policy
      end
    end
    expect(offenders).to be_empty,
                         "Unmarked StandardError containment branches:\n#{offenders.join("\n")}"
  end

  it 'routes diagnostic failures through the terminal non-throwing helper at core relays' do
    relay = File.read(File.join(lib_root, 'application/services/async_result_relay.rb'))
    state = File.read(File.join(lib_root, 'application/state/state_store.rb'))
    logger = File.read(File.join(lib_root, 'adapters/monitoring/logger_adapter.rb'))

    expect(relay).to include('ResilientDiagnostics')
    expect(state).to include('ResilientDiagnostics')
    expect(logger).to match(/rescue StandardError/)
  end
end
