# frozen_string_literal: true

module Shoko
  module Adapters::Input
    # Centralized key definitions to eliminate duplication and inconsistencies
    # across the codebase. All input handling should reference these definitions.
    module KeyDefinitions
      # Navigation keys
      NAVIGATION = {
        up: ['k', "\e[A", "\eOA"].freeze,
        down: ['j', "\e[B", "\eOB"].freeze,
        left: ['h', "\e[D", "\eOD"].freeze,
        right: ['l', "\e[C", "\eOC"].freeze,
      }.freeze

      # Action keys
      ACTIONS = {
        confirm: ["\r", "\n"].freeze,
        cancel: ["\e", "\x1B"].freeze,
        quit: ['q'].freeze,
        force_quit: ['Q'].freeze,
        space: [' '].freeze,
        backspace: ['\b', "\x7F", "\x08"].freeze,
        delete: ["\e[3~"].freeze,
      }.freeze

      # Reader-specific keys
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

      # Menu navigation keys
      MENU = {
        browse: ['f'].freeze,
        download_books: ['d'].freeze,
        settings: ['s'].freeze,
        search: ['S'].freeze,
        refresh_scan: ['r'].freeze,
      }.freeze

      # Utility methods for checking key membership
      module Helpers
        def self.navigation_key?(key)
          NAVIGATION.values.flatten.include?(key)
        end

        def self.up_key?(key)
          NAVIGATION[:up].include?(key)
        end

        def self.down_key?(key)
          NAVIGATION[:down].include?(key)
        end

        def self.confirm_key?(key)
          ACTIONS[:confirm].include?(key)
        end

        def self.cancel_key?(key)
          ACTIONS[:cancel].include?(key)
        end

        def self.quit_key?(key)
          ACTIONS[:quit].include?(key)
        end

        def self.backspace_key?(key)
          ACTIONS[:backspace].include?(key)
        end

        def self.escape_key?(key)
          ACTIONS[:cancel].include?(key)
        end

        # Check if key matches any keys in a definition
        def self.matches_keys?(key, key_list)
          key_list.include?(key)
        end

        # Create binding hash from key list and command
        def self.create_bindings(key_list, command)
          key_list.each_with_object({}) do |k, bindings|
            bindings[k] = command
          end
        end
      end
    end
  end
end
