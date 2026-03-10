# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::PopupPositionService do
  let(:reader_runtime_context) do
    instance_double(
      'ReaderRuntimeContext',
      terminal_size: Shoko::Core::Models::Session::TerminalSize.build(width: 80, height: 24)
    )
  end
  subject(:service) { described_class.new(reader_runtime_context: reader_runtime_context) }

  it 'positions popup below selection when there is room' do
    pos = service.calculate_popup_position({ x: 10, y: 5 }, 20, 4)

    expect(pos).to eq(x: 10, y: 6)
  end

  it 'clamps popup horizontally and vertically to stay on-screen' do
    pos = service.calculate_popup_position({ x: 79, y: 23 }, 10, 5)

    expect(pos[:x]).to eq(70)
    expect(pos[:y]).to eq(18)
  end
end
