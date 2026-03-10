# frozen_string_literal: true

require_relative 'delegation/sidebar'
require_relative 'delegation/annotation'
require_relative 'delegation/dictionary'
require_relative 'delegation/search'

module Shoko
  module Adapters
    module Input
      module Controllers
        module UiControllerDelegationFacade
          include UiControllerDelegation::Sidebar
          include UiControllerDelegation::Annotation
          include UiControllerDelegation::Dictionary
          include UiControllerDelegation::Search
        end
      end
    end
  end
end
