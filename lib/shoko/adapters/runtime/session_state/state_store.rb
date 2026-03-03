# frozen_string_literal: true

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
require_relative '../../../core/services/null_logger'
require_relative 'state_store/initial_state_builder'
require_relative 'state_store/transition_validator'
require_relative 'state_store/change_event_builder'
require_relative 'state_store/config_persistence'

module Shoko
  module Adapters
    module Runtime
      module SessionState
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
          # @param config_storage [Core::Ports::Outbound::ConfigStorage] Port for configuration persistence (required)
          # @param terminal_capabilities [Core::Ports::Outbound::TerminalCapabilities] Port for terminal capability detection (required)
          # @param logger [Core::Ports::Outbound::Logging, nil] Logger (optional)
          def initialize(event_bus, config_storage:, terminal_capabilities:, logger: nil)
            @event_bus = event_bus
            @config_storage = config_storage
            @terminal_capabilities = terminal_capabilities
            @logger = logger || Shoko::Core::Services::NullLogger.new
            @initial_state_builder = InitialStateBuilder.new(terminal_capabilities: terminal_capabilities)
            @transition_validator = TransitionValidator.new
            @change_event_builder = ChangeEventBuilder.new
            @config_persistence = ConfigPersistence.new(
              config_storage: config_storage,
              symbol_keys: SYMBOL_KEYS,
              line_spacing_aliases: LINE_SPACING_ALIASES,
              log_warn: method(:log_warn),
              log_error: method(:log_error)
            )
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
            events = nil
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
              events = build_change_events(old_state, new_state, updates)
            end

            emit_change_events(events)
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
            old_state = nil
            new_state = nil
            @mutex.synchronize do
              old_state = @state
              @state = build_initial_state
              new_state = @state
            end

            @event_bus.emit_event(:state_reset, { old_state: old_state, new_state: new_state })
          end

          # Validate state transition (override in subclasses)
          #
          # @param old_state [Hash] Previous state
          # @param new_state [Hash] Proposed new state
          # @param updates [Hash] Applied updates
          # @return [Boolean, String, nil] true/nil to allow, false to reject silently, String for rejection reason
          def valid_transition?(old_state, new_state, updates)
            @transition_validator.validate(old_state: old_state, new_state: new_state, updates: updates)
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

          # Configuration persistence methods
          def save_config
            @config_persistence.save(config: config_to_h, config_file: config_file, config_dir: config_dir)
          end

          def config_to_h
            get([:config])
          end

          # Dispatch an action object that can apply itself to the state store.
          def dispatch(action)
            action.apply(self)
          rescue ArgumentError
            raise ArgumentError, 'action must implement #apply'
          end

          private

          def build_initial_state
            @initial_state_builder.build
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

          def duplicate_node(node, clones)
            return node unless node.is_a?(Hash)
            return clones[node] if clones.key?(node)

            duped = node.dup
            clones[node] = duped
            duped
          # resilient-boundary
          rescue Shoko::Error => e
            log_debug('state_store.duplicate_node_failed', error: e.class.name, message: e.message)
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
              # resilient-boundary
              rescue Shoko::Error => e
                log_debug('state_store.deep_dup_value_failed', error: e.class.name, message: e.message)
                obj
              end
            end
          end

          def build_change_events(old_state, new_state, updates)
            @change_event_builder.build(old_state: old_state, new_state: new_state, updates: updates)
          end

          def emit_change_events(events)
            Array(events).each do |data|
              @event_bus.emit_event(:state_changed, data)
            end
          end

          def get_nested_value(hash, path)
            path.reduce(hash) { |h, key| h&.dig(key) }
          end

          def log_debug(message, **metadata)
            log(:debug, message, **metadata)
          end

          def log_warn(message, **metadata)
            log(:warn, message, **metadata)
          end

          def log_error(message, **metadata)
            log(:error, message, **metadata)
          end

          def log(level, message, **metadata)
            case level
            when :debug
              @logger.debug(message, **metadata)
            when :warn
              @logger.warn(message, **metadata)
            when :error
              @logger.error(message, **metadata)
            else
              raise ArgumentError, "unsupported log level: #{level.inspect}"
            end
          # resilient-boundary
          rescue Shoko::Error
            nil
          end

          # Load config from file on initialization
          def load_config_from_file
            config_updates = @config_persistence.load(config: get([:config]) || {}, config_file: config_file)
            update(config_updates) unless config_updates.empty?
          end
        end
      end
    end
  end
end
