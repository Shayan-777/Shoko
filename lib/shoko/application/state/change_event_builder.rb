# frozen_string_literal: true

module Shoko
  module Application
    module State
      class StateStore
        # Builds state_changed event payloads from committed updates.
        class ChangeEventBuilder
          def build(change_set:)
            change_set.each_with_object([]) do |change, events|
              events << {
                path: change.path,
                old_value: change.old_value,
                new_value: change.new_value,
                full_state: change_set.root,
              }
            end
          end
        end
      end
    end
  end
end
