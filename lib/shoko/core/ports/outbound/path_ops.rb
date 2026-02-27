# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Port for deterministic path transformations.
        module PathOps
          def expand_path(path, dir = nil)
            raise NotImplementedError, "#{self.class} must implement #expand_path"
          end

          def join(*parts)
            raise NotImplementedError, "#{self.class} must implement #join"
          end

          def basename(path)
            raise NotImplementedError, "#{self.class} must implement #basename"
          end
        end
      end
    end
  end
end
