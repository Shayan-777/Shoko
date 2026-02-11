# frozen_string_literal: true

require_relative '../../shared/key_definitions'

module Shoko
  module Adapters::Input
    # Input adapter compatibility wrapper around the shared key contract.
    module KeyDefinitions
      NAVIGATION = Shoko::Shared::KeyDefinitions::NAVIGATION
      ACTIONS = Shoko::Shared::KeyDefinitions::ACTIONS
      READER = Shoko::Shared::KeyDefinitions::READER
      MENU = Shoko::Shared::KeyDefinitions::MENU
      Helpers = Shoko::Shared::KeyDefinitions::Helpers
    end
  end
end
