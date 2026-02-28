# frozen_string_literal: true

module Shoko
  module Adapters
    module Runtime
      module SessionState
        class StateStore
          # Builds state_changed event payloads from committed updates.
          class ChangeEventBuilder
            def build(old_state:, new_state:, updates:)
              updates.each_with_object([]) do |(path, new_value), events|
                arr_path = Array(path)
                old_value = nested_value(old_state, arr_path)
                next if old_value == new_value

                events << {
                  path: arr_path,
                  old_value: old_value,
                  new_value: new_value,
                  full_state: new_state
                }
              end
            end

            private

            def nested_value(hash, path)
              path.reduce(hash) { |h, key| h&.dig(key) }
            end
          end
        end
      end
    end
  end
end
