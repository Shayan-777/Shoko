# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Strict chapter contract used by reader domain services.
        module ReaderChapter
          def title
            raise NotImplementedError, "#{self.class} must implement #title"
          end

          def lines
            raise NotImplementedError, "#{self.class} must implement #lines"
          end

          def metadata
            raise NotImplementedError, "#{self.class} must implement #metadata"
          end
        end
      end
    end
  end
end
