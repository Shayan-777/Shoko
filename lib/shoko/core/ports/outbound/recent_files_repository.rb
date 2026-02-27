# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Port interface for managing recent file history.
        module RecentFilesRepository
          # Add a recent file path.
          def add(path)
            raise NotImplementedError, "#{self.class} must implement #add"
          end

          # Load recent file entries.
          def load
            raise NotImplementedError, "#{self.class} must implement #load"
          end

          # Clear recent file history.
          def clear
            raise NotImplementedError, "#{self.class} must implement #clear"
          end
        end
      end
    end
  end
end
