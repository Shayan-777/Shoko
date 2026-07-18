# frozen_string_literal: true

require_relative '../../core/services/null_logger'
require_relative '../../shared/deep_structure'
require_relative '../../shared/download_source_policy'
require_relative '../../shared/theme_policy'
require_relative 'schema_registry'
require_relative 'change_set'
require_relative 'transition_validator'
require_relative 'config_persistence'

module Shoko
  module Application
    module State
      # Immutable-snapshot state store.
      #
      # The store is the application's single in-memory source of truth for
      # session state. It is constructed at the composition root, given a
      # populated `SchemaRegistry` whose fragments collectively define every
      # field of the initial state hash. The store has no external
      # counterparty — it is application infrastructure, not an adapter.
      #
      # Frozen-tree invariant: the state tree (every Hash, Array, and String
      # in it) is deep-frozen at all times, so `peek`/`peek_at`/`get` can
      # return internals without defensive copies and out-of-band mutation
      # raises instead of silently bypassing validation, locking, change
      # sets, and observers. Writes copy the update path, deep-dup inserted
      # values (callers keep ownership of their arguments), and freeze the
      # new structure before commit. Non-data leaf objects stored in state
      # are treated as opaque and never frozen here.
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

        def update(updates)
          @mutex.synchronize { commit_update(updates) }
        end

        def set(path, value)
          update({ path => value })
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
          Shoko::Shared::DeepStructure.deep_freeze(
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

        # Merge persisted config into state. Called by ObserverStateStore
        # during construction; the base store never loads it on its own.
        def load_config_from_file
          config_updates = @config_persistence.load(config: get([:config]) || {}, config_file: config_file)
          update(config_updates) unless config_updates.empty?
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
          raise ArgumentError, 'invalid download_source' unless Shoko::Shared::DownloadSourcePolicy.valid?(value)
        end

        def validate_theme(value)
          raise ArgumentError, "invalid theme: #{value.inspect}" unless Shoko::Shared::ThemePolicy.valid?(value)
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
