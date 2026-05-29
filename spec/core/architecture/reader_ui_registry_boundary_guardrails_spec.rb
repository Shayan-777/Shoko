# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Reader UI component registry boundary guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:observer_wiring_path) do
    File.join(
      root,
      'lib',
      'shoko',
      'composition',
      'container_factory',
      'controller_composition',
      'reader_runtime_assembler',
      'observer_wiring.rb'
    )
  end
  let(:state_observer_path) do
    File.join(root, 'lib', 'shoko', 'adapters', 'input', 'controllers', 'reader', 'state_observer.rb')
  end
  let(:registry_path) do
    File.join(root, 'lib', 'shoko', 'adapters', 'ui', 'state', 'reader_component_registry.rb')
  end
  let(:reader_view_schema_path) do
    File.join(root, 'lib', 'shoko', 'application', 'state', 'schema', 'reader_view.rb')
  end
  let(:forbidden_fields) do
    %i[
      popup_menu
      in_book_search_popup
      annotations_overlay
      annotation_editor_overlay
      translation_popup
      dictionary_popup
      dictionary_panel
    ]
  end

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue Errno::ENOENT
    ''
  end

  it 'keeps live UI component fields out of every layered reader snapshot contract' do
    offenders = forbidden_fields.flat_map do |field|
      types = {
        ReaderSessionSnapshot: Shoko::Application::Ports::Outbound::State::ReaderSessionSnapshot,
        ReaderViewSnapshot: Shoko::Application::Ports::Outbound::State::ReaderViewSnapshot,
        ReaderPaginationSnapshot: Shoko::Application::Ports::Outbound::State::ReaderPaginationSnapshot,
        ReaderSnapshot: Shoko::Application::Ports::Outbound::State::ReaderSnapshot,
      }
      types.filter_map { |name, klass| "#{name}:#{field}" if klass::FIELDS.include?(field) }
    end

    expect(offenders).to eq([]),
                         "Live UI component fields must not appear in reader snapshot contracts: #{offenders.join(', ')}"
  end

  it 'keeps live UI component fields out of layered schema fragments' do
    schema_content = non_comment_content(reader_view_schema_path)

    offenders = forbidden_fields.each_with_object([]) do |field, values|
      values << "reader_view_schema:#{field}" if schema_content.match?(/\b#{Regexp.escape(field.to_s)}\s*:/)
    end

    expect(offenders).to eq([]),
                         "Live UI component fields must not be reintroduced into schemas:\n#{offenders.join("\n")}"
  end

  it 'requires the UI-owned component registry and forbids observation of removed component-state paths' do
    expect(File.exist?(registry_path)).to be(true),
                                          "Reader UI component registry must exist for live UI objects: #{registry_path}"
    expect(non_comment_content(observer_wiring_path)).not_to include('%i[reader dictionary_panel]'),
                                                             "Observer wiring must not subscribe to removed dictionary_panel state path: #{observer_wiring_path}"
    expect(non_comment_content(state_observer_path)).not_to include('%i[reader dictionary_panel]'),
                                                            "Reader state observer must not react to removed dictionary_panel state path: #{state_observer_path}"
  end
end
