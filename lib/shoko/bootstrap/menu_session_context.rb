# frozen_string_literal: true

module Shoko
  module Bootstrap
      # Session-scoped context for menu flow coordination.
      class MenuSessionContext
        attr_accessor :last_opened_path
      end
  end
end
