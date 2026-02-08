# frozen_string_literal: true

module Shoko
  module Application
    module Composition
      # Session-scoped context for menu flow coordination.
      class MenuSessionContext
        attr_accessor :last_opened_path
      end
    end
  end
end
