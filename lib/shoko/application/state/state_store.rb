# frozen_string_literal: true

require_relative '../../core/services/null_logger'
require_relative '../../shared/deep_structure'
require 'shoko/core/policies/download_source_policy'
require 'shoko/core/policies/theme_policy'
require_relative 'schema_registry'
require_relative 'change_set'
require_relative 'transition_validator'
require_relative 'config_persistence'

module Shoko
  module Application
    module State
      # Immutable-snapshot state store with path-scoped observers.
      #
      # The store is the application's single in-memory source of truth for
      # session state. It is constructed at the composition root, given a
      # populated `SchemaRegistry` whose fragments collectively define every
      # field of the initial state hash. The store has no external
      # counterparty — it is application infrastructure, not an adapter.
      #
      # Closed-value invariant: the initial tree and every inserted value pass
      # through DeepStructure.admit. The complete graph is copied and frozen,
      # callers keep ownership of their arguments, and arbitrary opaque values
      # are rejected. Reads can therefore return internals without defensive
      # copies; out-of-band mutation raises instead of bypassing validation,
      # locking, change sets, and observers.
      #
      # Path observers are the store's single notification mechanism: consumers
      # subscribe to state paths and are notified after a committed update, on
      # the updating thread and outside the store's lock.
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

        SYMBOL_KEYS = %i[view_mode line_spacing download_source page_numbering_mode theme dictionary_backend
                         translator_backend].freeze
        LINE_SPACING_ALIASES = { tight: :compact, wide: :relaxed }.freeze
        private_constant :SYMBOL_KEYS, :LINE_SPACING_ALIASES

        # @param config_storage [Application::Ports::Outbound::ConfigStorage] Port for configuration persistence
        # @param terminal_capabilities [Application::Ports::Outbound::TerminalCapabilities]
        #   Port for terminal capability detection
        # @param schema_registry [SchemaRegistry] Composed schema fragments
        # @param logger [Application::Ports::Outbound::Logging, nil] Logger (optional)
        def initialize(config_storage:, terminal_capabilities:, schema_registry:, logger: nil)
          @config_storage = config_storage
          @terminal_capabilities = terminal_capabilities
          @schema_registry = schema_registry
          @logger = logger || Shoko::Core::Services::NullLogger.new
          @transition_validator = TransitionValidator.new
          @config_persistence = ConfigPersistence.new(
            config_storage: config_storage,
            symbol_keys: SYMBOL_KEYS,
            line_spacing_aliases: LINE_SPACING_ALIASES,
            log_warn: method(:log_warn),
            log_error: method(:log_error)
          )
          @state = build_initial_state
          @mutex = Mutex.new
          @observer_mutex = Mutex.new
          @observer_condition = ConditionVariable.new
          @observers_by_path = {}
          @observers_all = []
          @notification_queue = []
          @notification_drainer = nil
          load_persisted_config
        end

        def config_dir = @config_storage.config_dir

        def config_file = @config_storage.config_file

        def peek = @mutex.synchronize { @state }

        def peek_at(*path)
          @mutex.synchronize do
            Array(path).flatten.reduce(@state) { |state, key| state&.dig(key) }
          end
        end

        def get(path)
          @mutex.synchronize do
            path.reduce(@state) { |state, key| state&.dig(key) }
          end
        end

        # Commit updates, then notify observers outside the lock so a
        # subscriber may read the store (or update it again) without deadlock.
        def update(updates)
          envelope = nil
          should_drain = false
          change_set = @mutex.synchronize do
            committed = commit_update(updates)
            envelope, should_drain = enqueue_notification(committed) if committed && !committed.empty?
            committed
          end
          if should_drain
            drain_notification_queue
          elsif envelope && !notification_drainer_thread?
            wait_for_notification(envelope)
          end
          change_set
        end

        def set(path, value)
          update({ normalize_path(path) => value })
          value
        end

        # Register an observer for specific state paths; with no paths the
        # observer receives every change.
        # Observer must respond to `state_changed(path, old_value, new_value)`.
        #
        # @param observer [Object] Object implementing state_changed
        # @param paths [Array<Symbol, Array>] State paths to observe
        def add_observer(observer, *paths)
          @observer_mutex.synchronize do
            if paths.empty?
              @observers_all << observer unless @observers_all.include?(observer)
            else
              paths.each do |path|
                list = (@observers_by_path[normalize_path(path)] ||= [])
                list << observer unless list.include?(observer)
              end
            end
          end
          observer
        end

        # Remove observer from all paths
        #
        # @param observer [Object] Observer to remove
        def remove_observer(observer)
          @observer_mutex.synchronize do
            @observers_all.delete(observer)
            @observers_by_path.each_value { |list| list.delete(observer) }
          end
          observer
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
        # Typed-collaborator discipline: a non-conforming action fails fast
        # via NoMethodError, and errors raised inside #apply (including
        # validator ArgumentErrors) propagate untouched.
        def dispatch(action)
          action.apply(self)
        end

        private

        def build_initial_state
          Shoko::Shared::DeepStructure.admit(
            @schema_registry.initial_state(terminal_capabilities: @terminal_capabilities)
          )
        end

        def commit_update(updates)
          old_state = @state
          new_state = apply_updates(old_state, updates)
          return nil if old_state == new_state

          validation_result = valid_transition?(old_state, new_state, updates)
          unless validation_allowed?(validation_result)
            handle_invalid_transition(old_state, new_state, updates, validation_result)
            return nil
          end

          change_set = build_change_set(old_state: old_state, new_state: new_state, updates: updates)
          @state = new_state
          change_set
        end

        def validation_allowed?(validation_result) = validation_result == true || validation_result.nil?

        # Path-copy with freeze-on-commit: only nodes along update paths are
        # duplicated (collected in `created`); untouched branches stay the
        # already-frozen originals, so freezing just the created nodes at the
        # end keeps the whole-tree frozen invariant at O(path + value) cost.
        def apply_updates(state, updates)
          clones = {}.compare_by_identity
          created = []
          new_root = duplicate_node(state, clones: clones, created: created)

          updates.each do |path, value|
            validate_update(path, value)
            assign_update(new_root, Array(path), value, clones: clones, created: created)
          end

          created.each(&:freeze)
          new_root
        end

        def validate_update(path, value)
          validate_state_update(path, value)
        end

        def assign_update(root, keys, value, clones:, created:)
          parent = keys[0...-1].reduce(root) do |node, key|
            branch_for_update(node, key, clones: clones, created: created)
          end
          parent[keys.last] = Shoko::Shared::DeepStructure.admit(value)
          nil
        end

        def branch_for_update(node, key, clones:, created:)
          duplicated = duplicate_node(node[key], clones: clones, created: created)
          if duplicated.nil?
            duplicated = {}
            created << duplicated
          end
          node[key] = duplicated
          duplicated
        end

        def duplicate_node(node, clones:, created:)
          return node unless node.is_a?(Hash)
          return clones[node] if clones.key?(node)

          duped = node.dup
          clones[node] = duped
          created << duped
          duped
        end

        def build_change_set(old_state:, new_state:, updates:)
          ChangeSet.build(root_before: old_state, root_after: new_state, updates: updates)
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
        end

        # Merge persisted config into state during construction, writing the
        # file back when this is the first run.
        def load_persisted_config
          config_missing = !@config_storage.file_exist?(config_file)
          config_updates = @config_persistence.load(config: get([:config]) || {}, config_file: config_file)
          update(config_updates) unless config_updates.empty?
          save_config if config_missing
        end

        def enqueue_notification(change_set)
          @observer_mutex.synchronize do
            envelope = { change_set: change_set, complete: false }
            @notification_queue << envelope
            should_drain = @notification_drainer.nil?
            @notification_drainer = Thread.current if should_drain
            [envelope, should_drain]
          end
        end

        def notification_drainer_thread?
          @observer_mutex.synchronize { @notification_drainer.equal?(Thread.current) }
        end

        def wait_for_notification(envelope)
          @observer_mutex.synchronize do
            @observer_condition.wait(@observer_mutex) until envelope[:complete]
          end
        end

        # One thread drains committed change sets in commit order. Reentrant
        # updates append to the queue and are delivered after the current
        # callback set, avoiding deadlock and observer-order inversion.
        def drain_notification_queue
          loop do
            envelope = next_notification
            return unless envelope

            notify_observers_for_change_set(envelope[:change_set])
            complete_notification(envelope)
          end
        ensure
          release_notification_drainer_if_empty
        end

        def next_notification
          @observer_mutex.synchronize do
            envelope = @notification_queue.shift
            unless envelope
              @notification_drainer = nil
              @observer_condition.broadcast
            end
            envelope
          end
        end

        def complete_notification(envelope)
          @observer_mutex.synchronize do
            envelope[:complete] = true
            @observer_condition.broadcast
          end
        end

        def release_notification_drainer_if_empty
          @observer_mutex.synchronize do
            return unless @notification_drainer.equal?(Thread.current) && @notification_queue.empty?

            @notification_drainer = nil
            @observer_condition.broadcast
          end
        end

        def notify_observers_for_change_set(change_set)
          change_set.each do |change|
            notify_observers(normalize_path(change.path), change.old_value, change.new_value)
          end
        end

        # Each observer hears about a given change at most once, even when it
        # is subscribed to the exact path, a parent path, and globally.
        def notify_observers(path, old_value, new_value)
          observer_snapshot(path).each do |observer|
            safe_notify(observer, path, old_value, new_value)
          end
        end

        def observer_snapshot(path)
          @observer_mutex.synchronize do
            observers = []
            observers.concat(@observers_by_path.fetch(path, []))
            parent_paths(path).each { |parent| observers.concat(@observers_by_path.fetch(parent, [])) }
            observers.concat(@observers_all)
            identity_uniq(observers)
          end
        end

        def parent_paths(path)
          return [] if path.length <= 1

          (1...path.length).map { |index| path[0, index] }
        end

        def identity_uniq(observers)
          seen = {}.compare_by_identity
          observers.each_with_object([]) do |observer, unique|
            next if seen.key?(observer)

            seen[observer] = true
            unique << observer
          end
        end

        # Observer notification is an isolation boundary: observers are
        # arbitrary registered code, so one failing observer must not break
        # the state update or starve the remaining observers.
        def safe_notify(observer, path, old_value, new_value)
          observer.state_changed(path, old_value, new_value)
        # resilient-boundary
        rescue StandardError => e
          record_observer_notification_error(observer, path, e)
        end

        def record_observer_notification_error(observer, path, error)
          log_debug(
            'observer.notify failed',
            observer: observer.class.name,
            path: path,
            error_class: error.class.name,
            error: error.message
          )
          nil
        end

        # Normalize a path to a frozen array of symbols.
        def normalize_path(path)
          case path
          when Array then path.dup.freeze
          when Symbol then [path].freeze
          else [path.to_sym].freeze
          end
        end

        def validate_state_update(path, value)
          path_array = Array(path)

          case path_array
          when %i[reader current_chapter]
            validate_reader_update(value)
          when %i[config view_mode], %i[config download_source], %i[config theme], %i[config kitty_images]
            validate_config_update(path_array.last, value)
          when %i[ui terminal_width], %i[ui terminal_height]
            validate_terminal_dimension(value)
          end
        end

        def validate_reader_update(value)
          raise ArgumentError, 'current_chapter must be non-negative' if value.negative?
        end

        def validate_config_update(key, value)
          case key
          when :view_mode
            validate_view_mode(value)
          when :download_source
            validate_download_source(value)
          when :theme
            validate_theme(value)
          when :kitty_images
            validate_kitty_images(value)
          end
        end

        def validate_view_mode(value)
          raise ArgumentError, 'invalid view_mode' unless %i[single split].include?(value)
        end

        def validate_download_source(value)
          return if Shoko::Core::Policies::DownloadSourcePolicy.valid?(value)

          raise ArgumentError, 'invalid download_source'
        end

        def validate_theme(value)
          raise ArgumentError, "invalid theme: #{value.inspect}" unless Shoko::Core::Policies::ThemePolicy.valid?(value)
        end

        def validate_kitty_images(value)
          raise ArgumentError, 'kitty_images must be boolean' unless [true, false].include?(value)
        end

        def validate_terminal_dimension(value)
          raise ArgumentError, 'terminal dimensions must be positive' if value <= 0
        end
      end
    end
  end
end
