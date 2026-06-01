# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No swallowing fatal-input rescues' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:files) do
    [
      File.join(root, 'lib', 'shoko', 'adapters', 'input', 'cli.rb'),
      File.join(root, 'lib', 'shoko', 'adapters', 'input', 'controllers', 'menu', 'controller.rb'),
      File.join(root, 'lib', 'shoko', 'adapters', 'input', 'controllers', 'reader', 'lifecycle_runner.rb'),
      File.join(root, 'lib', 'shoko', 'application', 'unified_application.rb'),
      File.join(root, 'lib', 'shoko', 'application', 'workflows', 'menu', 'download_workflow.rb'),
      File.join(root, 'lib', 'shoko', 'application', 'workflows', 'menu', 'dictionary_workflow.rb'),
    ]
  end

  def rel(path)
    path.delete_prefix("#{root}/")
  end

  def rescue_body_lines(lines, rescue_index)
    rescue_indent = lines[rescue_index][/^\s*/].size
    index = rescue_index + 1
    body = []

    while index < lines.length
      line = lines[index]
      stripped = line.strip
      indent = line[/^\s*/].size

      break if indent <= rescue_indent && stripped.match?(/^(rescue|ensure|end)\b/)

      body << stripped unless stripped.empty? || stripped.start_with?('#')
      index += 1
    end

    body
  end

  def terminating_body?(body_lines)
    body_lines.any? do |line|
      line.start_with?('raise') || line.include?('terminate(2)') || line.include?('cleanup_and_exit(2')
    end
  end

  it 'requires fatal external-input rescue branches to terminate or re-raise' do
    offenders = []

    files.each do |path|
      lines = File.readlines(path)
      lines.each_with_index do |line, index|
        next unless line.match?(/^\s*rescue\s+Shoko::FatalExternalInputError/)

        body = rescue_body_lines(lines, index)
        next if terminating_body?(body)

        offenders << "#{rel(path)}:#{index + 1}"
      end
    end

    expect(offenders).to eq([]),
                         "Fatal external-input rescue branches must terminate or re-raise:\n#{offenders.join("\n")}"
  end
end
