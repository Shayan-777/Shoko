# frozen_string_literal: true

require_relative 'key_definitions'
require_relative '../../shared/text_sanitizer'

module Shoko
  module Adapters::Input
    # Factory for creating common input command patterns.
    module CommandFactory
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
        register_navigation(commands, :up, -1, selection_field, action_type, max_value_proc)
        register_navigation(commands, :down, +1, selection_field, action_type, max_value_proc)
        commands
      end

      def exit_commands(exit_action)
        commands = {}
        KeyDefinitions::ACTIONS[:cancel].each { |key| commands[key] = exit_action }
        commands
      end

      def menu_selection_commands
        commands = {}
        KeyDefinitions::ACTIONS[:confirm].each do |key|
          commands[key] = lambda do |ctx, _|
            ctx.handle_menu_selection
            :handled
          end
        end
        commands
      end

      def reader_navigation_commands
        reader = KeyDefinitions::READER
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
        reader = KeyDefinitions::READER
        actions = KeyDefinitions::ACTIONS
        commands = {}

        map_keys!(commands, reader[:toggle_view], :toggle_view_mode)
        map_keys!(commands, reader[:toggle_page_mode], :toggle_page_numbering_mode)
        map_keys!(commands, reader[:increase_spacing], :increase_line_spacing)
        map_keys!(commands, reader[:decrease_spacing], :decrease_line_spacing)
        map_keys!(commands, reader[:show_toc], :open_toc)
        map_keys!(commands, reader[:add_bookmark], :add_bookmark)
        map_keys!(commands, reader[:show_bookmarks], :open_bookmarks)
        map_keys!(commands, reader[:in_book_search], :open_in_book_search) if reader.key?(:in_book_search)
        map_keys!(commands, reader[:show_help], :show_help)

        map_keys!(commands, reader[:show_annotations], :open_annotations) if reader.key?(:show_annotations)
        map_keys!(commands, reader[:show_annotations_tab], :open_annotations_tab) if reader.key?(:show_annotations_tab)
        map_keys!(commands, reader[:rebuild_pagination], :rebuild_pagination) if reader.key?(:rebuild_pagination)
        if reader.key?(:invalidate_pagination)
          map_keys!(commands, reader[:invalidate_pagination], :invalidate_pagination_cache)
        end

        map_keys!(commands, actions[:quit], :quit_to_menu)
        map_keys!(commands, actions[:force_quit], :quit_application)
        commands
      end

      def text_input_commands(input_field, context_method = nil, cursor_field: nil)
        input_field = input_field.to_sym
        input_path = input_path_for(input_field)

        commands = {}
        KeyDefinitions::ACTIONS[:backspace].each do |key|
          commands[key] = lambda do |ctx, _|
            handle_backspace(ctx, key, input_field, input_path, context_method, cursor_field)
          end
        end
        KeyDefinitions::ACTIONS[:delete].each do |key|
          commands[key] = lambda do |ctx, _|
            current, cursor = current_and_cursor(ctx, input_path, cursor_field)
            new_value = splice_delete(current, cursor)
            apply_value(ctx, input_field, new_value, cursor_field, cursor)
            :handled
          end
        end

        commands[:__default__] = lambda do |ctx, key|
          char = key.to_s
          if Shoko::Shared::TextSanitizer.printable_char?(char)
            handle_character(ctx, key, input_field, input_path, context_method, cursor_field)
          else
            :pass
          end
        end

        commands
      end

      def handle_backspace(ctx, key, input_field, input_path, context_method, cursor_field)
        if context_method
          ctx.send(context_method, key)
        elsif input_path
          current, cursor_pos = current_and_cursor(ctx, input_path, cursor_field)
          new_value, new_cursor = splice_backspace(current, cursor_pos)
          apply_value(ctx, input_field, new_value, cursor_field, new_cursor)
        end
        :handled
      end
      private_class_method :handle_backspace

      def handle_character(ctx, key, input_field, input_path, context_method, cursor_field)
        if context_method
          ctx.send(context_method, key)
        elsif input_path
          current, cursor_pos = current_and_cursor(ctx, input_path, cursor_field)
          new_value, new_cursor = splice_insert(current, cursor_pos, key.to_s)
          apply_value(ctx, input_field, new_value, cursor_field, new_cursor)
        end
        :handled
      end
      private_class_method :handle_character

      def input_path_for(input_field)
        {
          search_query: %i[menu search_query],
          download_query: %i[menu download_query],
          dictionary_query: %i[menu dictionary_query],
        }[input_field]
      end
      private_class_method :input_path_for

      def current_and_cursor(ctx, input_path, cursor_field)
        return ['', 0] unless input_path

        current = current_value(ctx, input_path)
        cursor_pos = determine_cursor(ctx, cursor_field, current)
        [current, cursor_pos]
      end
      private_class_method :current_and_cursor

      def determine_cursor(ctx, cursor_field, current)
        if cursor_field
          reader = resolve_menu_state_reader(ctx)
          cursor_val = begin
            reader&.public_send(cursor_field)
          rescue StandardError
            nil
          end
          (cursor_val || current.length).to_i
        else
          current.length
        end
      end
      private_class_method :determine_cursor

      def apply_value(ctx, input_field, new_value, cursor_field, new_cursor)
        if cursor_field && !new_cursor.nil?
          dispatch_menu(ctx, input_field => new_value, cursor_field => new_cursor)
        else
          dispatch_menu(ctx, input_field => new_value)
        end
      end
      private_class_method :apply_value

      def register_navigation(commands, direction, step, selection_field, action_type, max_value_proc)
        handler = navigation_handler(step, selection_field, action_type, max_value_proc)
        Array(KeyDefinitions::NAVIGATION[direction]).each { |key| commands[key] = handler }
      end
      private_class_method :register_navigation

      def navigation_handler(step, selection_field, action_type, max_value_proc)
        lambda do |ctx, _|
          current = value_at(ctx, action_type == :menu ? :menu : :reader, selection_field)
          target = if step.negative?
                     [current + step, 0].max
                   else
                     max_val = max_value_proc.call(ctx)
                     (current + step).clamp(0, max_val)
                   end
          dispatch_for(ctx, action_type, selection_field, target)
          :handled
        end
      end
      private_class_method :navigation_handler

      def map_keys!(commands, keys, action)
        Array(keys).each { |key| commands[key] = action }
        commands
      end
      private_class_method :map_keys!

      def dispatch_for(ctx, action_type, field, value)
        case action_type
        when :menu
          dispatch_menu(ctx, field => value)
        when :sidebar
          state_writer = resolve_state_writer(ctx)
          state_writer&.update_sidebar({ field => value })
        end
      end
      private_class_method :dispatch_for

      def dispatch_menu(ctx, hash)
        menu_writer = resolve_menu_state_writer(ctx)
        menu_writer&.update_menu(hash)
      end
      private_class_method :dispatch_menu

      def value_at(ctx, base, field)
        case base
        when :menu
          reader = resolve_menu_state_reader(ctx)
          return 0 unless reader

          begin
            reader.public_send(field)
          rescue StandardError
            0
          end
        when :reader
          reader = resolve_reader_state_reader(ctx)
          return 0 unless reader

          begin
            reader.public_send(field)
          rescue StandardError
            0
          end
        else
          0
        end
      end
      private_class_method :value_at

      def current_value(ctx, input_path)
        # input_path is like [:menu, :search_query]
        return '' unless input_path && input_path.length == 2

        base, field = input_path
        case base
        when :menu
          reader = resolve_menu_state_reader(ctx)
          return '' unless reader

          begin
            reader.public_send(field)
          rescue StandardError
            ''
          end || ''
        else
          ''
        end
      end
      private_class_method :current_value

      def resolve_menu_state_reader(ctx)
        return ctx.menu_state_reader if ctx.respond_to?(:menu_state_reader)
        nil
      end
      private_class_method :resolve_menu_state_reader

      def resolve_menu_state_writer(ctx)
        return ctx.menu_state_writer if ctx.respond_to?(:menu_state_writer)
        nil
      end
      private_class_method :resolve_menu_state_writer

      def resolve_state_writer(ctx)
        return ctx.state_writer if ctx.respond_to?(:state_writer)
        nil
      end
      private_class_method :resolve_state_writer

      def resolve_reader_state_reader(ctx)
        return ctx.reader_state_reader if ctx.respond_to?(:reader_state_reader)
        nil
      end
      private_class_method :resolve_reader_state_reader

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
