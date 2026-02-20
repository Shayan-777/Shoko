# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Controllers::SidebarMouseHandler do
  class DummySidebarMouseHandler
    include Shoko::Application::Controllers::SidebarMouseHandler
  end

  subject(:handler) { DummySidebarMouseHandler.new }

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
