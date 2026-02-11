# frozen_string_literal: true

module Shoko
  module Shared
    # Canonical key contract shared across adapters.
    module KeyDefinitions
      NAVIGATION = {
        up: ['k', "\e[A", "\eOA"].freeze,
        down: ['j', "\e[B", "\eOB"].freeze,
        left: ['h', "\e[D", "\eOD"].freeze,
        right: ['l', "\e[C", "\eOC"].freeze,
      }.freeze

      ACTIONS = {
        confirm: ["\r", "\n"].freeze,
        cancel: ["\e", "\x1B"].freeze,
        quit: ['q'].freeze,
        force_quit: ['Q'].freeze,
        space: [' '].freeze,
        save: ["\x13", 'S'].freeze,
        backspace: ['\b', "\x7F", "\x08"].freeze,
        delete: ["\e[3~"].freeze,
      }.freeze

      READER = {
        next_page: ['l', ' ', "\e[C", "\eOC"].freeze,
        prev_page: ['h', "\e[D", "\eOD"].freeze,
        scroll_down: ['j', "\e[B", "\eOB"].freeze,
        scroll_up: ['k', "\e[A", "\eOA"].freeze,
        next_chapter: %w[n N].freeze,
        prev_chapter: ['p'].freeze,
        go_to_start: ['g'].freeze,
        go_to_end: ['G'].freeze,
        toggle_view: %w[v V].freeze,
        toggle_page_mode: ['P'].freeze,
        increase_spacing: ['+'].freeze,
        decrease_spacing: ['-'].freeze,
        show_toc: %w[t T].freeze,
        add_bookmark: ['b'].freeze,
        show_bookmarks: ['B'].freeze,
        show_annotations_tab: ['A'].freeze,
        in_book_search: ['s'].freeze,
        show_help: ['?'].freeze,
        show_annotations: ["\u0001"].freeze,
        rebuild_pagination: ['R'].freeze,
        invalidate_pagination: ['I'].freeze,
      }.freeze

      MENU = {
        browse: ['f'].freeze,
        download_books: ['d'].freeze,
        settings: ['s'].freeze,
        search: ['S'].freeze,
        refresh_scan: ['r'].freeze,
      }.freeze

      module Helpers
        module_function

        def navigation_key?(key)
          NAVIGATION.values.flatten.include?(key)
        end

        def up_key?(key)
          NAVIGATION[:up].include?(key)
        end

        def down_key?(key)
          NAVIGATION[:down].include?(key)
        end

        def confirm_key?(key)
          ACTIONS[:confirm].include?(key)
        end

        def cancel_key?(key)
          ACTIONS[:cancel].include?(key)
        end

        def quit_key?(key)
          ACTIONS[:quit].include?(key)
        end

        def backspace_key?(key)
          ACTIONS[:backspace].include?(key)
        end

        def escape_key?(key)
          ACTIONS[:cancel].include?(key)
        end

        def matches_keys?(key, key_list)
          key_list.include?(key)
        end

        def create_bindings(key_list, command)
          key_list.each_with_object({}) do |mapped_key, bindings|
            bindings[mapped_key] = command
          end
        end
      end
    end
  end
end
