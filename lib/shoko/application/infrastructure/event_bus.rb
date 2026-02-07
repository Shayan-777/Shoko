# frozen_string_literal: true

require_relative '../../adapters/state/event_bus'

module Shoko
  module Application::Infrastructure
    EventBus = Shoko::Adapters::State::EventBus
    Event = Shoko::Adapters::State::Event
  end
end
