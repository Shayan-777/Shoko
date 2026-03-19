# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module MouseableReaderSupport
          # Handles runtime input/mouse bootstrapping concerns for the mouseable reader.
          module RuntimeInputSupport
            def run
              terminal_service.enable_mouse
              drain_input_buffer
              super
            ensure
              terminal_service.disable_mouse
            end

            def drain_input_buffer
              drained = 0
              while terminal_service.read_key
                drained += 1
                break if drained > 20
              end
            end

            def read_input_keys(timeout: nil)
              key = terminal_service.read_input_with_mouse(timeout: timeout)
              return [] unless key

              keys = [key]
              while (extra = terminal_service.read_key)
                keys << extra
                break if keys.size > 10
              end

              filter_mouse_sequences(keys)
            end

            def clear_selection!
              @reader_session_mutator.update_reader(popup_menu: nil, hovered_inline_link: nil)
              @mouse_handler&.reset
              @reader_session_mutator.clear_selection
            end
          end
        end
      end
    end
  end
end
