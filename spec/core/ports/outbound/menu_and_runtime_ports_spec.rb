# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Menu and runtime outbound port contracts' do
  def build_implementation(port_module)
    Class.new do
      include port_module
    end.new
  end

  def expect_contract_methods_to_raise(implementation, methods)
    methods.each do |method_name, args, kwargs|
      expect do
        if kwargs
          implementation.public_send(method_name, *args, **kwargs)
        else
          implementation.public_send(method_name, *args)
        end
      end.to raise_error(NotImplementedError)
    end
  end

  it 'defines MenuWorkflowStateReader contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::MenuWorkflowStateReader)
    methods = %i[
      current_menu_mode
      selected_library_index
      selected_annotation_record
      selected_annotation_book_path
      annotation_editor_text
      dictionary_entries
    ].map { |name| [name, [], nil] }

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines MenuWorkflowStateWriter contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::MenuWorkflowStateWriter)
    methods = [
      [:set_download_state, [{}], nil],
      [:set_dictionary_state, [{}], nil],
      [:set_annotation_state, [{}], nil],
      [:set_loading_state, [], nil]
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines TerminalSession contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::TerminalSession)
    methods = [
      [:setup, [], nil],
      [:cleanup, [], nil],
      [:size, [], nil]
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines AppModeRunner contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::AppModeRunner)
    methods = [
      [:run_reader, [], { path: '/tmp/book.epub' }],
      [:run_menu, [], nil]
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines AnnotationEditorLauncher contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::AnnotationEditorLauncher)
    methods = [
      [:open_editor, [], { text: 'a', range: {}, chapter_index: 0, annotation: {} }]
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines WallClock and IdGenerator contract methods' do
    wall_clock = build_implementation(Shoko::Core::Ports::Outbound::WallClock)
    id_generator = build_implementation(Shoko::Core::Ports::Outbound::IdGenerator)

    expect { wall_clock.utc_now }.to raise_error(NotImplementedError)
    expect { id_generator.uuid }.to raise_error(NotImplementedError)
  end
end
