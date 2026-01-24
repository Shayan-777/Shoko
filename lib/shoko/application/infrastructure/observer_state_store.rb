# frozen_string_literal: true

require_relative 'state_store'

module Shoko
  module Application::Infrastructure
    # StateStore with observer pattern support; central app state with observer notifications
    class ObserverStateStore < StateStore
      # @param event_bus [EventBus] Event bus for state change events
      # @param config_storage [Core::Ports::ConfigStorage] Port for configuration persistence (required)
      # @param terminal_capabilities [Core::Ports::TerminalCapabilities] Port for terminal capability detection (required)
      def initialize(event_bus, config_storage:, terminal_capabilities:)
        super(event_bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities)
        @observers_by_path = Hash.new { |h, k| h[k] = [] }
        @observers_all = []
        config_missing = !File.exist?(config_file)
        load_config_from_file
        save_config if config_missing && respond_to?(:save_config)
      end

      # Register an observer for specific state paths
      # Observer should respond to `state_changed(path, old_value, new_value)`
      #
      # @param observer [Object] Object implementing state_changed method
      # @param *paths [Array<Symbol|Array>] State paths to observe
      def add_observer(observer, *paths)
        if paths.empty?
          @observers_all << observer unless @observers_all.include?(observer)
        else
          paths.each do |path|
            normalized_path = normalize_path(path)
            unless @observers_by_path[normalized_path].include?(observer)
              @observers_by_path[normalized_path] << observer
            end
          end
        end
      end

      # Remove observer from all paths
      #
      # @param observer [Object] Observer to remove
      def remove_observer(observer)
        @observers_all.delete(observer)
        @observers_by_path.each_value { |list| list.delete(observer) }
      end

      # Override update to include observer notifications
      # Supports both update(path, value) and update({path => value}) formats for compatibility
      def update(path_or_updates, value = nil)
        if value.nil?
          # New format: update({path => value, path2 => value2})
          updates = path_or_updates
          old_state = current_state
          super(updates)
          notify_observers_for_updates(old_state, updates)
        else
          # Legacy format: update(path, value)
          path = path_or_updates
          normalized_path = normalize_path(path)
          old_value = get(normalized_path)
          super({ normalized_path => value })
          notify_observers(normalized_path, old_value, value) unless old_value == value
        end
      end

      # Override set to include observer notifications
      def set(path, value)
        old_value = get(path)
        super
        return value if old_value == value

        normalized_path = normalize_path(path)
        notify_observers(normalized_path, old_value, value)
        value
      end

      private

      def notify_observers_for_updates(old_state, updates)
        updates.each do |path, new_value|
          arr = Array(path)
          old_value = get_nested_value(old_state, arr)
          next if old_value == new_value

          normalized_path = normalize_path(arr)
          notify_observers(normalized_path, old_value, new_value)
        end
      end

      def notify_observers(path, old_value, new_value)
        # Notify path-specific observers
        @observers_by_path[path].each do |observer|
          safe_notify(observer, path, old_value, new_value)
        end

        # Notify observers watching parent paths
        notify_parent_path_observers(path, old_value, new_value)

        # Notify global observers
        @observers_all.each do |observer|
          safe_notify(observer, path, old_value, new_value)
        end
      end

      # Notify observers watching parent paths (e.g., [:reader] when [:reader, :mode] changes)
      def notify_parent_path_observers(path, old_value, new_value)
        len = path.length
        return if len <= 1

        (1...len).each do |i|
          parent_path = path[0, i]
          @observers_by_path[parent_path].each do |observer|
            safe_notify(observer, path, old_value, new_value)
          end
        end
      end

      # Safely notify observer, catching any exceptions
      def safe_notify(observer, path, old_value, new_value)
        return unless observer.respond_to?(:state_changed)

        observer.state_changed(path, old_value, new_value)
      rescue StandardError
        # Silently ignore observer errors to prevent breaking application flow
        nil
      end

      # Normalize path to array format
      def normalize_path(path)
        case path
        when Array then path
        when Symbol then [path]
        else [path.to_sym]
        end
      end
    end
  end
end
