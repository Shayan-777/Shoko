# frozen_string_literal: true

require 'spec_helper'

# The small set of genuine app-specific invariants the constitution's §V
# target shape allows alongside the rule specs: single-owner seams that no
# generic layer rule covers.
RSpec.describe 'Domain invariants' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  it 'keeps set_message implementation centralized in message_notifier' do
    files = Dir[File.join(lib_root, 'adapters', 'input', 'controllers', '**', '*.rb')]
    offenders = files.reject { |path| path.end_with?('support/message_notifier.rb') }
                     .select { |path| File.read(path).match?(/^\s*def\s+set_message\(/) }

    expect(offenders).to eq([]),
                         "Duplicate set_message implementations detected:\n#{offenders.sort.join("\n")}"
  end

  it 'contains hardcoded keyword highlighting to approved rendering files only' do
    allowed = [
      File.join(lib_root, 'adapters', 'ui', 'constants', 'highlighting.rb'),
      File.join(lib_root, 'adapters', 'ui', 'rendering', 'line', 'line_content_composer.rb'),
      File.join(lib_root, 'adapters', 'ui', 'rendering', 'line', 'inline_segment_highlighter.rb'),
    ]
    pattern = /Constants::Highlighting::(?:HIGHLIGHT_WORDS|HIGHLIGHT_PATTERNS|QUOTE_PATTERNS)/

    offenders = Dir[File.join(lib_root, '**', '*.rb')].select do |path|
      next false if allowed.include?(path)

      non_comment_content(path).match?(pattern)
    end

    expect(offenders).to eq([]),
                         "Hardcoded highlighting constants leaked outside approved files:\n" \
                         "#{offenders.map { |p| p.delete_prefix("#{root}/") }.join("\n")}"
  end

  it 'forbids backend-specific error-string diagnosis in core dictionary service' do
    content = non_comment_content(File.join(lib_root, 'core', 'services', 'dictionary_service.rb'))
    forbidden = [
      /database disk image is malformed/i,
      /file is not a database/i,
      /no such table/i,
      /sqlite/i,
      /permission denied/i,
    ]

    offenders = forbidden.select { |pattern| content.match?(pattern) }
    expect(offenders).to eq([]),
                         'Core dictionary service must not parse backend-specific error strings.'
  end
end
