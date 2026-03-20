# frozen_string_literal: true

require_relative '../../shared/key_definitions'
require_relative '../../shared/text_sanitizer'
require_relative 'command_factory/state_access'
require_relative 'command_factory/text_input_commands'

module Shoko
  module Adapters
    module Input
      # Factory for creating common input command patterns.
      module CommandFactory
        NavigationConfig = Data.define(:step, :selection_field, :action_type, :max_value_proc)

        module_function

        def navigation_commands(_context, selection_field, max_value_proc)
          selection_field = selection_field.to_sym
          action_type = case selection_field
                        when :selected, :browse_selected
                          :menu
                        when :sidebar_toc_selected, :sidebar_bookmarks_selected, :sidebar_annotations_selected
                          :sidebar
                        end
          return {} unless action_type

          commands = {}
          register_navigation(commands, :up, navigation_config(-1, selection_field, action_type, max_value_proc))
          register_navigation(commands, :down, navigation_config(+1, selection_field, action_type, max_value_proc))
          commands
        end

        def exit_commands(exit_action)
          commands = {}
          Shoko::Shared::KeyDefinitions::ACTIONS[:cancel].each { |key| commands[key] = exit_action }
          commands
        end

        def menu_selection_commands
          commands = {}
          Shoko::Shared::KeyDefinitions::ACTIONS[:confirm].each do |key|
            commands[key] = lambda do |ctx, _|
              ctx.handle_menu_selection
              :handled
            end
          end
          commands
        end

        def reader_navigation_commands
          reader = Shoko::Shared::KeyDefinitions::READER
          commands = {}
          map_keys!(commands, reader[:next_page], :next_page)
          map_keys!(commands, reader[:prev_page], :prev_page)
          map_keys!(commands, reader[:scroll_down], :scroll_down)
          map_keys!(commands, reader[:scroll_up], :scroll_up)
          map_keys!(commands, reader[:next_chapter], :next_chapter)
          map_keys!(commands, reader[:prev_chapter], :prev_chapter)
          map_keys!(commands, reader[:go_to_start], :go_to_start)
          map_keys!(commands, reader[:go_to_end], :go_to_end)
          commands
        end

        def reader_control_commands
          reader = Shoko::Shared::KeyDefinitions::READER
          commands = {}

          map_keys!(commands, reader[:add_bookmark], :add_bookmark)
          commands
        end

        def text_input_commands(input_field, cursor_field: nil)
          TextInputCommands.build(input_field, cursor_field: cursor_field)
        end

        def register_navigation(commands, direction, config)
          handler = navigation_handler(config)
          Array(Shoko::Shared::KeyDefinitions::NAVIGATION[direction]).each { |key| commands[key] = handler }
        end
        private_class_method :register_navigation

        def navigation_handler(config)
          lambda do |ctx, _|
            current = StateAccess.value_at(ctx, config.action_type == :menu ? :menu : :reader, config.selection_field)
            target = if config.step.negative?
                       [current + config.step, 0].max
                     else
                       max_val = config.max_value_proc.call(ctx)
                       (current + config.step).clamp(0, max_val)
                     end
            StateAccess.dispatch_for(ctx, config.action_type, config.selection_field, target)
            :handled
          end
        end
        private_class_method :navigation_handler

        def navigation_config(step, selection_field, action_type, max_value_proc)
          NavigationConfig.new(
            step: step,
            selection_field: selection_field,
            action_type: action_type,
            max_value_proc: max_value_proc
          )
        end
        private_class_method :navigation_config

        def map_keys!(commands, keys, action)
          Array(keys).each { |key| commands[key] = action }
          commands
        end
        private_class_method :map_keys!
      end
    end
  end
end
