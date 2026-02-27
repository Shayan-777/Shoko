# frozen_string_literal: true

require_relative 'setup_flow/lookup_flow'
require_relative 'setup_flow/interaction_handlers'
require_relative 'setup_flow/submission_flow'
require_relative 'setup_flow/download_support'
require_relative 'setup_flow/popup_state_support'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dictionary
          # Composes setup-flow modules used by DictionaryController.
          module SetupFlowSupport
            include SetupFlow::LookupFlow
            include SetupFlow::InteractionHandlers
            include SetupFlow::SubmissionFlow
            include SetupFlow::DownloadSupport
            include SetupFlow::PopupStateSupport
          end
        end
      end
    end
  end
end
