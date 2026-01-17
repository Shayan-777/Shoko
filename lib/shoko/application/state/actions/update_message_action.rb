# frozen_string_literal: true

require_relative 'base_action'
require_relative '../../../adapters/output/terminal/terminal_sanitizer'

module Shoko
  module Application
    module Actions
      # Action for updating the status message
      class UpdateMessageAction < BaseAction
        def initialize(message)
          super(message: message)
        end

        def apply(state)
          msg = payload[:message]
          safe = if msg.nil?
                   nil
                 else
                   Shoko::Adapters::Output::Terminal::TerminalSanitizer.sanitize(msg.to_s, preserve_newlines: false,
                                                                                           preserve_tabs: false)
                 end
          state.update({ %i[reader message] => safe })
        end
      end
    end
  end
end
