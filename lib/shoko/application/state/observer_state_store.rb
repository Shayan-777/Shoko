# frozen_string_literal: true

require_relative 'state_store'

module Shoko
  module Application
    module State
      # StateStore with observer-pattern support.
      #
      # Adds path-scoped subscriptions on top of the base state store so that
      # consumers can react to specific state-path changes without consuming
      # the broadcast event stream.
      class ObserverStateStore < StateStore
        # @param event_bus [EventBus] Event bus for state change events
        # @param config_storage [Application::Ports::Outbound::ConfigStorage] Port for configuration persistence (required)
        # @param terminal_capabilities [Application::Ports::Outbound::TerminalCapabilities]
        #   Port for terminal capability detection (required)
        # @param schema_registry [SchemaRegistry] Composed schema fragments (required)
        # @param logger [Application::Ports::Outbound::Logging, nil] Logger (optional)
        def initialize(event_bus, config_storage:, terminal_capabilities:, schema_registry:, logger: nil)
          super
          @observers_by_path = Hash.new { |h, k| h[k] = [] }
          @observers_all = []
          config_missing = !@config_storage.file_exist?(config_file)
          load_config_from_file
          save_config if config_missing
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

        # Override update to include observer notifications.
        # Accepts update({path => value, path2 => value2}) only.
        def update(updates)
          change_set = super
          notify_observers_for_change_set(change_set) if change_set && !change_set.empty?
          change_set
        end

        # Override set to include observer notifications
        def set(path, value)
          normalized_path = normalize_path(path)
          update({ normalized_path => value })
          value
        end

        private

        def notify_observers_for_change_set(change_set)
          change_set.each do |change|
            normalized_path = normalize_path(change.path)
            notify_observers(normalized_path, change.old_value, change.new_value)
          end
        end

        def notify_observers(path, old_value, new_value)
          notified = {}.compare_by_identity
          change = [path, old_value, new_value]

          # Notify path-specific observers
          notify_observer_list(@observers_by_path[path], change, notified)

          # Notify observers watching parent paths
          notify_parent_path_observers(change, notified)

          # Notify global observers
          notify_observer_list(@observers_all, change, notified)
        end

        # Notify observers watching parent paths (e.g., [:reader] when [:reader, :mode] changes)
        def notify_parent_path_observers(change, notified)
          path = change[0]
          len = path.length
          return if len <= 1

          (1...len).each do |i|
            parent_path = path[0, i]
            notify_observer_list(@observers_by_path[parent_path], change, notified)
          end
        end

        def notify_observer_list(observers, change, notified)
          path, old_value, new_value = change
          Array(observers).each do |observer|
            next if notified.key?(observer)

            safe_notify(observer, path, old_value, new_value)
            notified[observer] = true
          end
        end

        # Safely notify observer, catching any exceptions
        def safe_notify(observer, path, old_value, new_value)
          observer.state_changed(path, old_value, new_value)
        rescue ArgumentError
          raise ArgumentError, "#{observer.class} must implement #state_changed(path, old_value, new_value)"
        # resilient-boundary
        rescue Shoko::Error => e
          log_debug('observer.notify failed', observer: observer.class.name, path: path, error: e.message)
          nil
        end

        # Normalize path to array format
        def normalize_path(path)
          case path
          when Array then path.dup.freeze
          when Symbol then [path].freeze
          else [path.to_sym].freeze
          end
        end
      end
    end
  end
end
