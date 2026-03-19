# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Reader UI registry boundary guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:initial_state_builder_path) do
    File.join(root, 'lib', 'shoko', 'adapters', 'runtime', 'session_state', 'state_store', 'initial_state_builder.rb')
  end
  let(:reader_selectors_path) do
    File.join(root, 'lib', 'shoko', 'adapters', 'runtime', 'session_state', 'selectors', 'reader_selectors.rb')
  end
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
    File.join(root, 'lib', 'shoko', 'adapters', 'runtime', 'session_state', 'reader_ui_session_registry.rb')
  end
  let(:forbidden_fields) do
    %i[
      popup_menu
      in_book_search_popup
      annotations_overlay
      annotation_editor_overlay
      dictionary_popup
      dictionary_panel
    ]
  end

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue Errno::ENOENT
    ''
  end

  it 'keeps live UI component fields out of the core reader snapshot contract' do
    offenders = Shoko::Core::Models::Session::ReaderSnapshotFields & forbidden_fields

    expect(offenders).to eq([]),
                         "Live UI component fields must not exist in ReaderSnapshotFields: #{offenders.join(', ')}"
  end

  it 'keeps live UI component fields out of state initialization and selectors' do
    state_content = non_comment_content(initial_state_builder_path)
    selector_content = non_comment_content(reader_selectors_path)

    offenders = forbidden_fields.each_with_object([]) do |field, values|
      values << "initial_state_builder:#{field}" if state_content.match?(/\b#{Regexp.escape(field.to_s)}\s*:/)
      values << "reader_selectors:#{field}" if selector_content.match?(/def\s+#{Regexp.escape(field.to_s)}\b/)
    end

    expect(offenders).to eq([]),
                         "Live UI component fields must not be reintroduced into state builders/selectors:\n#{offenders.join("\n")}"
  end

  it 'keeps dictionary layout observation off removed state paths and requires the adapter-owned registry' do
    expect(File.exist?(registry_path)).to be(true),
                                          "Reader UI session registry must exist for adapter-owned live objects: #{registry_path}"
    expect(non_comment_content(observer_wiring_path)).not_to include('%i[reader dictionary_panel]'),
                                                             "Observer wiring must not subscribe to removed dictionary_panel state path: #{observer_wiring_path}"
    expect(non_comment_content(state_observer_path)).not_to include('%i[reader dictionary_panel]'),
                                                            "Reader state observer must not react to removed dictionary_panel state path: #{state_observer_path}"
  end
end
