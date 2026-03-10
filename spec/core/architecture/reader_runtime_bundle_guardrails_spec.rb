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

    expect(members & %i[session services ui persistence runtime_state]).to eq([])
    expect(members).to include(
      :reader_state_reader,
      :reader_session_mutator,
      :reader_session_store,
      :rendering_factory,
      :reader_ui_dependencies
    )
  end
end
