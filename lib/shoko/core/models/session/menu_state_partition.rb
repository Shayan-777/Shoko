# frozen_string_literal: true

require_relative 'menu_session_snapshot'
require_relative 'menu_transient_snapshot'

module Shoko
  module Core
    module Models
      module Session
        # Splits menu updates across durable session and transient workflow state.
        module MenuStatePartition
          module_function

          def split(attributes)
            attributes.each_with_object([{}, {}]) do |(field, value), targets|
              session_attributes, transient_attributes = targets
              if MenuTransientSnapshotFields.include?(field)
                transient_attributes[field] = value
              else
                session_attributes[field] = value
              end
            end
          end
        end
      end
    end
  end
end
