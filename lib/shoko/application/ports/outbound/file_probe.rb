# frozen_string_literal: true

module Shoko
  module Application
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

          # Return the file's modification time as an ISO 8601 string, or
          # nil if the file is missing. Implementations handle the
          # underlying filesystem failure (SystemCallError) and return nil
          # — the port promises that callers see either a valid timestamp
          # or nil, never a raw filesystem exception.
          def mtime(path)
            raise NotImplementedError, "#{self.class} must implement #mtime"
          end
        end
      end
    end
  end
end
