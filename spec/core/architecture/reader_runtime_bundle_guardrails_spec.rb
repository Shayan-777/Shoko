# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Reader runtime bundle guardrails' do
  let(:assembler) { Shoko::Composition::ContainerFactory::ControllerComposition::ReaderRuntimeAssembler }

  it 'keeps removed nested runtime bundle constants deleted' do
    removed_constants = %i[SessionBundle RuntimeStateBundle ServiceBundle UiBundle PersistenceBundle]

    offenders = removed_constants.select { |const_name| assembler.const_defined?(const_name, false) }

    expect(offenders).to eq([]),
                         "Removed reader runtime bundle constants reappeared: #{offenders.join(', ')}"
  end

  it 'keeps runtime context direct instead of nesting bundle accessors' do
    members = assembler::RuntimeContext.members

    expect(members).to eq(%i[platform state ui services reader_ui_dependencies])
    expect(assembler::ReaderPlatformContext.members).to eq(
      %i[
        doc
        terminal_service
        terminal_session
        page_calculator
        clock
        process_control
        async_executor
        display_capabilities
        instrumentation
        logger
      ]
    )
    expect(assembler::ReaderStateContext.members).to eq(
      %i[
        reader_session_store
        reader_session_mutator
        app_config_store
        observer_registry
        reader_runtime_context
        rendered_content_reader
        notification_writer
        reader_component_registry
      ]
    )
    expect(assembler::ReaderUiContext.members).to eq(
      %i[
        layout_service
        layout_metrics
        wrapping_service
        formatting_service
        ui_component_factory
        input_system_factory
        rendering_factory
        dictionary_ui_session
        in_book_search_ui_session
        toc_ui_session
        translator_ui_session
        notes_ui_session
        annotation_overlay_ui_session
      ]
    )
  end
end
