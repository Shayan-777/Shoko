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
      (reader_state_reader|sidebar_state_reader|ui_state_reader|pagination_state_writer|reader_state_writer|ui_loading_writer)
      \s*&?\.\s*
      ([A-Za-z_][A-Za-z0-9_]*[!?=]?)
    /x
  end

  def allowed_methods
    {
      'reader_state_reader' => Shoko::Core::Ports::Outbound::ReaderNavigationReader.instance_methods(false).map(&:to_s).to_set,
      'sidebar_state_reader' => Shoko::Core::Ports::Outbound::SidebarStateReader.instance_methods(false).map(&:to_s).to_set,
      'ui_state_reader' => Shoko::Core::Ports::Outbound::UiStateReader.instance_methods(false).map(&:to_s).to_set,
      'pagination_state_writer' => Shoko::Core::Ports::Outbound::PaginationStateWriter.instance_methods(false).map(&:to_s).to_set,
      'reader_state_writer' => Shoko::Core::Ports::Outbound::ReaderStateWriter.instance_methods(false).map(&:to_s).to_set,
      'ui_loading_writer' => Shoko::Core::Ports::Outbound::UiLoadingWriter.instance_methods(false).map(&:to_s).to_set
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
