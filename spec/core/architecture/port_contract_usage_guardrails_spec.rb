# frozen_string_literal: true

require 'spec_helper'
require 'set'

RSpec.describe 'Outbound port contract usage' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:application_files) { Dir[File.join(lib_root, 'application', '**', '*.rb')] }
  let(:port_var_pattern) do
    /
      (?<![A-Za-z0-9_])
      @?
      (reader_state_reader|sidebar_state_reader|ui_state_reader)
      \s*&?\.\s*
      ([A-Za-z_][A-Za-z0-9_]*[!?=]?)
    /x
  end

  def allowed_methods
    {
      'reader_state_reader' => Shoko::Adapters::Runtime::SessionState::ReaderSessionView.instance_methods(false).map(&:to_s).to_set,
      'sidebar_state_reader' => Shoko::Adapters::Runtime::SessionState::ReaderSessionView.instance_methods(false).map(&:to_s).to_set,
      'ui_state_reader' => Shoko::Adapters::Runtime::SessionState::ReaderUiStateView.instance_methods(false).map(&:to_s).to_set
    }
  end

  it 'limits application-layer calls to the declared outbound port methods' do
    offenders = []
    allowed = allowed_methods

    application_files.each do |path|
      File.readlines(path).each_with_index do |line, index|
        content = line.sub(/\s+#.*\z/, '')
        next if content.strip.empty?

        content.to_enum(:scan, port_var_pattern).map { Regexp.last_match }.each do |match|
          port_var = match[1]
          method_name = match[2]
          next if allowed.fetch(port_var).include?(method_name)

          offenders << "#{path}:#{index + 1} #{port_var}.#{method_name}"
        end
      end
    end

    expect(offenders).to eq([]),
                         "Application calls methods outside outbound port contracts:\n#{offenders.sort.join("\n")}"
  end
end
