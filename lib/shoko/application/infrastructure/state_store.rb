# frozen_string_literal: true

require 'fileutils'
begin
  require 'json'
rescue NameError => e
  raise unless e.name == :Fragment

  # Ensure JSON::Fragment exists for compatibility with JSON parsing in some environments.
  module JSON
    Fragment = Object unless const_defined?(:Fragment)
  end
  require 'json'
end

module Shoko
  module Application::Infrastructure
    # Immutable state store with event-driven updates.
    # Single source of truth for application state with validation.
    #
    # This class follows hexagonal architecture principles:
    # - Configuration persistence goes through ConfigStorage port
    # - Terminal capability detection goes through TerminalCapabilities port
    class StateStore
      # Error raised when a state transition is invalid
      class StateUpdateError < StandardError
        attr_reader :old_state, :new_state, :updates, :reason

        def initialize(message, old_state: nil, new_state: nil, updates: nil, reason: nil)
          super(message)
          @old_state = old_state
          @new_state = new_state
          @updates = updates
          @reason = reason
        end
      end

      attr_reader :event_bus

      SYMBOL_KEYS = %i[view_mode line_spacing page_numbering_mode theme dictionary_backend].freeze
      LINE_SPACING_ALIASES = {
        tight: :compact,
        wide: :relaxed,
      }.freeze
      private_constant :SYMBOL_KEYS, :LINE_SPACING_ALIASES

      # @param event_bus [EventBus] Event bus for state change events
      # @param config_storage [Core::Ports::ConfigStorage] Port for configuration persistence (required)
      # @param terminal_capabilities [Core::Ports::TerminalCapabilities] Port for terminal capability detection (required)
      def initialize(event_bus, config_storage:, terminal_capabilities:)
        @event_bus = event_bus
        @config_storage = config_storage
        @terminal_capabilities = terminal_capabilities
        @state = build_initial_state
        @mutex = Mutex.new
      end

      # Get the configuration directory path via injected port
      def config_dir
        @config_storage.config_dir
      end

      # Get the configuration file path via injected port
      def config_file
        @config_storage.config_file
      end

      # Cheap, read-only reference to the current state (no deep copy).
      # Callers must not mutate the returned object.
      def peek
        @mutex.synchronize { @state }
      end

      # Get current state snapshot (immutable)
      #
      # @return [Hash] Current state
      def current_state
        @mutex.synchronize { deep_dup(@state, true) }
      end

      # Get value at specific path
      #
      # @param path [Array<Symbol>] Path to value
      # @return [Object] Value at path
      def get(path)
        @mutex.synchronize do
          path.reduce(@state) { |state, key| state&.dig(key) }
        end
      end

      # Update state and emit events
      #
      # @param updates [Hash] Hash of path => value updates
      # @raise [StateUpdateError] if the transition is invalid
      def update(updates)
        @mutex.synchronize do
          old_state = @state
          new_state = apply_updates(old_state, updates)

          return if old_state == new_state

          # Validate the transition before committing
          validation_result = valid_transition?(old_state, new_state, updates)
          unless validation_result == true || validation_result.nil?
            handle_invalid_transition(old_state, new_state, updates, validation_result)
            return
          end

          @state = new_state
          emit_change_events(old_state, new_state, updates)
        end
      end

      # Update single path
      #
      # @param path [Array<Symbol>] Path to update
      # @param value [Object] New value
      def set(path, value)
        update({ path => value })
      end

      # Reset to initial state
      def reset!
        @mutex.synchronize do
          old_state = @state
          @state = build_initial_state
          @event_bus.emit_event(:state_reset, { old_state: old_state, new_state: @state })
        end
      end

      # Validate state transition (override in subclasses)
      #
      # @param old_state [Hash] Previous state
      # @param new_state [Hash] Proposed new state
      # @param updates [Hash] Applied updates
      # @return [Boolean, String, nil] true/nil to allow, false to reject silently, String for rejection reason
      def valid_transition?(old_state, new_state, updates)
        result = validate_reader_transitions(old_state, new_state, updates)
        return result unless result == true

        result = validate_pagination_transitions(old_state, new_state, updates)
        return result unless result == true

        validate_sidebar_transitions(old_state, new_state, updates)
      end

      # Handle invalid state transitions
      # Override in subclasses for custom behavior (e.g., logging instead of raising)
      #
      # @param old_state [Hash] Previous state
      # @param new_state [Hash] Proposed new state
      # @param updates [Hash] Applied updates
      # @param reason [String, Boolean] Reason for rejection or false
      # @raise [StateUpdateError] by default
      def handle_invalid_transition(old_state, new_state, updates, reason)
        message = reason.is_a?(String) ? reason : 'Invalid state transition'
        raise StateUpdateError.new(
          message,
          old_state: old_state,
          new_state: new_state,
          updates: updates,
          reason: reason
        )
      end

      # Convenience methods for compatibility with legacy callers
      def terminal_size_changed?(width, height)
        last_width = get(%i[reader last_width])
        last_height = get(%i[reader last_height])
        width != last_width || height != last_height
      end

      def update_terminal_size(width, height)
        update({
                 %i[reader last_width] => width,
                 %i[reader last_height] => height,
                 %i[ui terminal_width] => width,
                 %i[ui terminal_height] => height,
               })
      end

      def apply_terminal_dimensions(width, height)
        return unless width && height

        update_terminal_size(width, height)
      end

      # State snapshot for persistence
      def reader_snapshot
        {
          current_chapter: get(%i[reader current_chapter]),
          page_offset: get(%i[reader single_page]),
          mode: get(%i[reader mode]).to_s,
          timestamp: Time.now.iso8601,
        }
      end

      # Restore reader state from snapshot
      def restore_reader_from(snapshot)
        update({
                 %i[reader current_chapter] => snapshot['current_chapter'] || 0,
                 %i[reader single_page] => snapshot['page_offset'] || 0,
                 %i[reader left_page] => snapshot['page_offset'] || 0,
                 %i[reader mode] => (snapshot['mode'] || 'read').to_sym,
               })
      end

      # Configuration persistence methods
      def save_config
        ensure_config_dir
        write_config_file
      rescue StandardError
        # Ignore save errors
      end

      def config_to_h
        get([:config])
      end

      # Dispatch Application::Actions to update state explicitly
      def dispatch(action)
        return unless action.respond_to?(:apply)

        action.apply(self)
      end

      private

      def build_initial_state
        {
          reader: {
            # Position state
            current_chapter: 0,
            left_page: 0,
            right_page: 0,
            single_page: 0,
            current_page_index: 0,

            # Mode and UI state
            mode: :read,
            selection: nil,
            message: nil,
            running: true,

            # Lists and selections
            bookmarks: [],
            annotations: [],

            # Pagination state
            page_map: [],
            total_pages: 0,
            pages_per_chapter: [],

            # Terminal sizing
            last_width: 0,
            last_height: 0,
            page_offset: 0,

            # Dynamic pagination
            dynamic_page_map: nil,
            dynamic_total_pages: 0,
            dynamic_chapter_starts: [],
            last_dynamic_width: 0,
            last_dynamic_height: 0,

            # UI state
            rendered_lines: {},
            popup_menu: nil,
            annotations_overlay: nil,
            annotation_editor_overlay: nil,

            # Sidebar state
            sidebar_visible: false,
            sidebar_active_tab: :toc,
            sidebar_toc_selected: 0,
            sidebar_annotations_selected: 0,
            sidebar_bookmarks_selected: 0,
            sidebar_toc_filter: nil,
            sidebar_toc_filter_active: false,
            sidebar_toc_collapsed: nil,
          },

          menu: {
            selected: 0,
            mode: :menu,
            browse_selected: 0,
            settings_selected: 1,
            search_query: '',
            search_cursor: 0,
            search_active: false,
            download_query: '',
            download_cursor: 0,
            download_selected: 0,
            download_results: [],
            download_count: 0,
            download_next: nil,
            download_prev: nil,
            download_status: :idle,
            download_message: '',
            download_progress: 0.0,
            dictionary_selected: 0,
            dictionary_query: '',
            dictionary_cursor: 0,
            dictionary_results: [],
            dictionary_status: :idle,
            dictionary_message: '',
            dictionary_progress: 0.0,
          },

          config: {
            view_mode: :split,
            line_spacing: :compact,
            page_numbering_mode: :dynamic,
            theme: :dark,
            show_page_numbers: true,
            highlight_quotes: true,
            highlight_keywords: false,
            prefetch_pages: 20,
            kitty_images: @terminal_capabilities.kitty_graphics_supported?,
            dictionary_source_lang: 'auto',
            dictionary_target_lang: 'en',
            dictionary_path: nil,
            dictionary_backend: nil,
          },

          ui: {
            terminal_width: 80,
            terminal_height: 24,
          },
        }
      end

      def apply_updates(state, updates)
        # Copy only the branches we need to touch instead of duplicating the entire tree.
        clones = {}.compare_by_identity
        new_root = duplicate_node(state, clones)

        updates.each do |path, value|
          validate_update(path, value)
          keys = Array(path)
          target = new_root
          keys[0...-1].each do |key|
            existing = target[key]
            duplicated = duplicate_node(existing, clones)
            duplicated = {} if duplicated.nil?
            target[key] = duplicated
            target = duplicated
          end
          target[keys.last] = value
        end

        new_root
      end

      def validate_update(path, value)
        # Add validation logic here
        path_array = Array(path)

        case path_array
        when %i[reader current_chapter]
          raise ArgumentError, 'current_chapter must be non-negative' if value.negative?
        when %i[config view_mode]
          raise ArgumentError, 'invalid view_mode' unless %i[single split].include?(value)
        when %i[config kitty_images]
          raise ArgumentError, 'kitty_images must be boolean' unless [true, false].include?(value)
        when %i[ui terminal_width], %i[ui terminal_height]
          raise ArgumentError, 'terminal dimensions must be positive' if value <= 0
        end
      end

      def set_nested(hash, path, value)
        *keys, last_key = path

        if keys.empty?
          hash[last_key] = value
        else
          # Create mutable path to target
          target = hash
          keys.each do |key|
            target[key] = {} unless target.key?(key)
            target = target[key]
          end
          target[last_key] = value
        end
      end

      def duplicate_node(node, clones)
        return node unless node.is_a?(Hash)
        return clones[node] if clones.key?(node)

        duped = node.dup
        clones[node] = duped
        duped
      rescue StandardError
        node
      end

      def deep_dup(obj, freeze_result = false)
        case obj
        when Hash
          result = obj.transform_values { |v| deep_dup(v, freeze_result) }
          freeze_result ? result.freeze : result
        when Array
          result = obj.map { |v| deep_dup(v, freeze_result) }
          freeze_result ? result.freeze : result
        else
          begin
            obj.dup
          rescue StandardError
            obj
          end
        end
      end

      def emit_change_events(old_state, new_state, updates)
        updates.each do |path, new_value|
          arr_path = Array(path)
          old_value = get_nested_value(old_state, arr_path)
          next if old_value == new_value

          @event_bus.emit_event(:state_changed, {
                                  path: arr_path,
                                  old_value: old_value,
                                  new_value: new_value,
                                  full_state: new_state,
                                })
        end
      end

      def get_nested_value(hash, path)
        path.reduce(hash) { |h, key| h&.dig(key) }
      end

      def ensure_config_dir
        @config_storage.ensure_config_dir
      rescue StandardError
        nil
      end

      def write_config_file
        payload = JSON.pretty_generate(config_to_h)
        @config_storage.atomic_write(config_file, payload)
      rescue StandardError
        nil
      end

      # Load config from file on initialization
      def load_config_from_file
        return unless File.exist?(config_file)

        data = parse_config_file(config_file)
        apply_config_data(data) if data
      rescue StandardError
        # Use defaults on error
      end

      def parse_config_file(path)
        content = @config_storage.read_file(path)
        return nil unless content

        JSON.parse(content, symbolize_names: true)
      rescue StandardError
        nil
      end

      def apply_config_data(data)
        config_updates = {}
        data.each do |key, value|
          next unless get([:config]).key?(key)

          value = value.to_sym if SYMBOL_KEYS.include?(key) && value.respond_to?(:to_sym)
          value = LINE_SPACING_ALIASES.fetch(value, value) if key == :line_spacing
          next unless valid_config_value?(key, value)

          config_updates[[:config, key]] = value
        end
        update(config_updates) unless config_updates.empty?
      end

      def valid_config_value?(key, value)
        case key
        when :view_mode
          %i[single split].include?(value)
        when :kitty_images
          value.is_a?(TrueClass) || value.is_a?(FalseClass)
        else
          true
        end
      end

      # Validate reader state transitions
      def validate_reader_transitions(_old_state, new_state, updates)
        updates.each do |path, value|
          path_arr = Array(path)
          next unless path_arr.first == :reader

          case path_arr
          when %i[reader current_chapter]
            total = new_state.dig(:reader, :total_chapters) || 0
            if total.positive? && value >= total
              return "current_chapter (#{value}) cannot exceed total_chapters (#{total})"
            end
          when %i[reader left_page], %i[reader right_page], %i[reader single_page]
            return "#{path_arr.last} cannot be negative" if value.negative?
          when %i[reader current_page_index]
            return 'current_page_index cannot be negative' if value.negative?
          end
        end
        true
      end

      # Validate pagination state transitions
      def validate_pagination_transitions(_old_state, new_state, updates)
        updates.each do |path, value|
          path_arr = Array(path)
          next unless path_arr.first == :reader

          case path_arr
          when %i[reader current_page_index]
            total = new_state.dig(:reader, :dynamic_total_pages) || 0
            if total.positive? && value >= total
              return "current_page_index (#{value}) cannot exceed dynamic_total_pages (#{total})"
            end
          when %i[reader total_pages], %i[reader dynamic_total_pages]
            return "#{path_arr.last} cannot be negative" if value.negative?
          end
        end
        true
      end

      # Validate sidebar state transitions
      def validate_sidebar_transitions(_old_state, _new_state, updates)
        updates.each do |path, value|
          path_arr = Array(path)
          next unless path_arr.first == :reader

          case path_arr
          when %i[reader sidebar_toc_selected],
               %i[reader sidebar_annotations_selected],
               %i[reader sidebar_bookmarks_selected]
            return "#{path_arr.last} cannot be negative" if value.negative?
          when %i[reader sidebar_active_tab]
            valid_tabs = %i[toc bookmarks annotations]
            return "Invalid sidebar tab: #{value}" unless valid_tabs.include?(value)
          end
        end
        true
      end
    end
  end
end
