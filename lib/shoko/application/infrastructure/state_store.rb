# frozen_string_literal: true

require_relative '../../adapters/state/state_store'

module Shoko
  module Application::Infrastructure
    StateStore = Shoko::Adapters::State::StateStore
  end
end
