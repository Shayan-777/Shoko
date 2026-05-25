# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Port for persistent, per-book display metadata cached for library browsing.
        module DisplayMetadataCache
          def fetch(path:, size:, modified:)
            raise NotImplementedError, "#{self.class} must implement #fetch"
          end

          def write_success(path:, size:, modified:, metadata:)
            raise NotImplementedError, "#{self.class} must implement #write_success"
          end

          def write_error(path:, size:, modified:, error_class:, error_message:)
            raise NotImplementedError, "#{self.class} must implement #write_error"
          end
        end
      end
    end
  end
end
