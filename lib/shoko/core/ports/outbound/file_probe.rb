# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Port for filesystem probing operations.
        module FileProbe
          def exist?(path)
            raise NotImplementedError, "#{self.class} must implement #exist?"
          end

          def file?(path)
            raise NotImplementedError, "#{self.class} must implement #file?"
          end

          def size(path)
            raise NotImplementedError, "#{self.class} must implement #size"
          end
        end
      end
    end
  end
end
