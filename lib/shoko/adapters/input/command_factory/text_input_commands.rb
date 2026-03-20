# frozen_string_literal: true

require_relative 'state_access'

module Shoko
  module Adapters
    module Input
      module CommandFactory
        # Builds common text-input command groups for menu-like modes.
        module TextInputCommands
          Definition = Data.define(:input_field, :input_path, :cursor_field)

          module_function

          def build(input_field, cursor_field: nil)
            definition = Definition.new(
              input_field: input_field.to_sym,
              input_path: input_path_for(input_field),
              cursor_field: cursor_field
            )

            commands = {}
            register_backspace_commands(commands, definition)
            register_delete_commands(commands, definition)
            commands[:__default__] = character_input_command(definition)
            commands
          end

          def register_backspace_commands(commands, definition)
            Shoko::Shared::KeyDefinitions::ACTIONS[:backspace].each do |key|
              commands[key] = lambda do |ctx, _|
                handle_backspace(ctx, definition)
              end
            end
          end
          private_class_method :register_backspace_commands

          def register_delete_commands(commands, definition)
            Shoko::Shared::KeyDefinitions::ACTIONS[:delete].each do |key|
              commands[key] = lambda do |ctx, _|
                current, cursor = current_and_cursor(ctx, definition)
                new_value = splice_delete(current, cursor)
                apply_value(ctx, definition, new_value, cursor)
                :handled
              end
            end
          end
          private_class_method :register_delete_commands

          def character_input_command(definition)
            lambda do |ctx, key|
              char = key.to_s
              return :pass unless Shoko::Shared::TextSanitizer.printable_char?(char)

              handle_character(ctx, key, definition)
            end
          end
          private_class_method :character_input_command

          def handle_backspace(ctx, definition)
            return :handled unless definition.input_path

            current, cursor_pos = current_and_cursor(ctx, definition)
            new_value, new_cursor = splice_backspace(current, cursor_pos)
            apply_value(ctx, definition, new_value, new_cursor)
            :handled
          end
          private_class_method :handle_backspace

          def handle_character(ctx, key, definition)
            return :handled unless definition.input_path

            current, cursor_pos = current_and_cursor(ctx, definition)
            new_value, new_cursor = splice_insert(current, cursor_pos, key.to_s)
            apply_value(ctx, definition, new_value, new_cursor)
            :handled
          end
          private_class_method :handle_character

          def input_path_for(input_field)
            {
              search_query: %i[menu search_query],
              download_query: %i[menu download_query],
              dictionary_query: %i[menu dictionary_query],
            }[input_field.to_sym]
          end
          private_class_method :input_path_for

          def current_and_cursor(ctx, definition)
            return ['', 0] unless definition.input_path

            current = StateAccess.current_value(ctx, definition.input_path)
            cursor_pos = determine_cursor(ctx, definition, current)
            [current, cursor_pos]
          end
          private_class_method :current_and_cursor

          def determine_cursor(ctx, definition, current)
            return current.length unless definition.cursor_field

            reader = StateAccess.resolve_menu_state_reader(ctx)
            cursor_val = StateAccess.menu_numeric_value(reader, definition.cursor_field)
            (cursor_val || current.length).to_i
          end
          private_class_method :determine_cursor

          def apply_value(ctx, definition, new_value, new_cursor)
            updates = { definition.input_field => new_value }
            updates[definition.cursor_field] = new_cursor if definition.cursor_field && !new_cursor.nil?
            StateAccess.dispatch_menu(ctx, updates)
          end
          private_class_method :apply_value

          def splice_backspace(current, cursor)
            return [current, cursor] unless cursor.positive?

            before = current[0, cursor - 1] || ''
            after = current[cursor..] || ''
            [before + after, cursor - 1]
          end
          private_class_method :splice_backspace

          def splice_insert(current, cursor, char)
            before = current[0, cursor] || ''
            after = current[cursor..] || ''
            [before + char + after, cursor + 1]
          end
          private_class_method :splice_insert

          def splice_delete(current, cursor)
            return current unless cursor < current.length

            before = current[0, cursor] || ''
            after = current[(cursor + 1)..] || ''
            before + after
          end
          private_class_method :splice_delete
        end
      end
    end
  end
end
