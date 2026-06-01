# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::SidebarMouseHandler do
  subject(:handler) do
    described_class.new(
      mouse_handler: nil, coordinate_service: nil, terminal_service: nil,
      render_coordinator: nil, ui_controller: nil, clock: nil, redraw: -> {}
    )
  end

  describe '#sidebar_wheel_event_allowed?' do
    it 'throttles rapid same-direction wheel events' do
      allow(handler).to receive(:monotonic_time).and_return(
        10.0,
        10.01,
        10.08
      )

      expect(handler.send(:sidebar_wheel_event_allowed?, 1)).to be(true)
      expect(handler.send(:sidebar_wheel_event_allowed?, 1)).to be(false)
      expect(handler.send(:sidebar_wheel_event_allowed?, 1)).to be(true)
    end

    it 'allows immediate direction changes' do
      allow(handler).to receive(:monotonic_time).and_return(
        20.0,
        20.01,
        20.02
      )

      expect(handler.send(:sidebar_wheel_event_allowed?, 1)).to be(true)
      expect(handler.send(:sidebar_wheel_event_allowed?, -1)).to be(true)
      expect(handler.send(:sidebar_wheel_event_allowed?, -1)).to be(false)
    end
  end
end
