# frozen_string_literal: true

require_relative 'commands'

module Shoko
  module Adapters
    module Input
      # Dispatches keys through a stack of active input modes.
      class Dispatcher
        def initialize(context)
          @context = context
          @command_map = {}
          @mode_stack = []
        end

        def handle_key(key)
          return if key.nil?

          @mode_stack.reverse_each do |mode|
            bindings = @command_map[mode] || {}
            cmd = bindings[key] || bindings[:__default__]
            next unless cmd

            result = Commands.execute(cmd, @context, key)
            return result if result == :handled
          end
          :pass
        end

        def push_mode(mode, bindings = {})
          @mode_stack << mode
          @command_map[mode] = bindings if bindings && !bindings.empty?
        end

        def pop_mode
          @mode_stack.pop
        end

        def remove_mode(mode)
          @mode_stack.delete(mode)
          @command_map.delete(mode)
        end

        def clear
          @mode_stack.clear
        end

        # Register bindings for a mode without activating it
        def register_mode(mode, bindings)
          @command_map[mode] = bindings
        end

        # Activate a single mode (clears the stack, then pushes)
        def activate(mode)
          clear
          push_mode(mode, @command_map[mode] || {})
        end

        # Activate a full stack of modes in order; last wins on dispatch
        def activate_stack(modes)
          clear
          modes.each { |m| push_mode(m, @command_map[m] || {}) }
        end

        def mode_stack
          @mode_stack.dup
        end
      end
    end
  end
end
