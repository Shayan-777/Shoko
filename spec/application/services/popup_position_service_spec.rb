# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::PopupPositionService do
  let(:terminal_service) { instance_double('TerminalService', size: [24, 80]) }
  subject(:service) { described_class.new(terminal_service: terminal_service) }

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
