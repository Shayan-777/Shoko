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
require_relative '../../../shared/download_source_policy'
require_relative '../../../shared/theme_policy'
require_relative 'state_store/change_set'
require_relative 'state_store/initial_state_builder'
require_relative 'state_store/transition_validator'
require_relative 'state_store/change_event_builder'
require_relative 'state_store/config_persistence'
require_relative 'state_store/update_validation'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Immutable state store with event-driven updates.
        # Single source of truth for application state with validation.
        class StateStore
          include StateStoreUpdateValidation

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

          SYMBOL_KEYS = %i[view_mode line_spacing download_source page_numbering_mode theme dictionary_backend].freeze
          LINE_SPACING_ALIASES = { tight: :compact, wide: :relaxed }.freeze
          private_constant :SYMBOL_KEYS, :LINE_SPACING_ALIASES

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

          def config_dir = @config_storage.config_dir

          def config_file = @config_storage.config_file

          def peek = @mutex.synchronize { @state }

          def peek_at(*path)
            @mutex.synchronize do
              Array(path).flatten.reduce(@state) { |state, key| state&.dig(key) }
            end
          end

          def current_state = @mutex.synchronize { deep_dup(@state, true) }

          def get(path)
            @mutex.synchronize do
              path.reduce(@state) { |state, key| state&.dig(key) }
            end
          end

          def update(updates)
            change_set, events = @mutex.synchronize { commit_update(updates) }

            emit_change_events(events)
            change_set
          end

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

          def config_to_h = get([:config])

          # Dispatch an action object that can apply itself to the state store.
          def dispatch(action)
            action.apply(self)
          rescue ArgumentError
            raise ArgumentError, 'action must implement #apply'
          end

          private

          def build_initial_state = @initial_state_builder.build

          def commit_update(updates)
            old_state = @state
            new_state = apply_updates(old_state, updates)
            return [nil, nil] if old_state == new_state

            validation_result = valid_transition?(old_state, new_state, updates)
            unless validation_allowed?(validation_result)
              handle_invalid_transition(old_state, new_state, updates, validation_result)
              return [nil, nil]
            end

            change_set = build_change_set(old_state: old_state, new_state: new_state, updates: updates)
            @state = new_state
            [change_set, build_change_events(change_set)]
          end

          def validation_allowed?(validation_result) = validation_result == true || validation_result.nil?

          def apply_updates(state, updates)
            clones = {}.compare_by_identity
            new_root = duplicate_node(state, clones)

            updates.each do |path, value|
              validate_update(path, value)
              assign_update(new_root, Array(path), value, clones)
            end

            new_root
          end

          def validate_update(path, value)
            validate_state_update(path, value)
          end

          def assign_update(root, keys, value, clones)
            target = root
            keys[0...-1].each do |key|
              existing = target[key]
              duplicated = duplicate_node(existing, clones) || {}
              target[key] = duplicated
              target = duplicated
            end
            target[keys.last] = value
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

          def deep_dup(obj, freeze_result: false)
            case obj
            when Hash
              result = obj.transform_values { |v| deep_dup(v, freeze_result: freeze_result) }
              freeze_result ? result.freeze : result
            when Array
              result = obj.map { |v| deep_dup(v, freeze_result: freeze_result) }
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

          def build_change_set(old_state:, new_state:, updates:)
            ChangeSet.build(root_before: old_state, root_after: new_state, updates: updates)
          end

          def build_change_events(change_set) = @change_event_builder.build(change_set: change_set)

          def emit_change_events(events)
            Array(events).each do |data|
              @event_bus.emit_event(:state_changed, data)
            end
          end

          def log_debug(message, **metadata) = log(:debug, message, **metadata)

          def log_warn(message, **metadata) = log(:warn, message, **metadata)

          def log_error(message, **metadata) = log(:error, message, **metadata)

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
