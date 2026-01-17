# frozen_string_literal: true

require_relative 'base_repository'

module Shoko
  module Adapters::Storage::Repositories
    # Repository for configuration persistence, abstracting the underlying storage mechanism.
    #
    # This repository provides a clean domain interface for configuration operations,
    # using the StateStore as the single source of truth for all configuration data.
    #
    # @example Getting configuration
    #   repo = ConfigRepository.new(dependencies)
    #   view_mode = repo.view_mode
    #   line_spacing = repo.line_spacing
    #
    # @example Updating configuration
    #   repo.update_view_mode(:split)
    #   repo.update_line_spacing(:relaxed)
    class ConfigRepository < BaseRepository
      LINE_SPACING_ALIASES = {
        tight: :compact,
        wide: :relaxed,
      }.freeze

      LINE_SPACING_ALLOWED = %i[compact normal relaxed].freeze

      # Default configuration values
      DEFAULT_CONFIG = {
        view_mode: :split,
        page_numbering_mode: :dynamic,
        show_page_numbers: true,
        line_spacing: :compact,
        highlight_quotes: true,
        input_debounce_ms: 100,
        search_highlight_timeout: 2000,
        auto_save_interval: 30,
        theme: :default,
      }.freeze

      def initialize(dependencies)
        super
        @state_store = dependencies.resolve(:global_state)
      end

      # Get the current view mode
      #
      # @return [Symbol] Current view mode (:split or :single)
      def view_mode
        get_config_value(:view_mode, DEFAULT_CONFIG[:view_mode])
      end

      # Update the view mode
      #
      # @param mode [Symbol] New view mode (:split or :single)
      # @return [Boolean] True if updated successfully
      def update_view_mode(mode)
        validate_enum_value(:view_mode, mode, %i[split single])
        update_config_value(:view_mode, mode)
      end

      # Get the current page numbering mode
      #
      # @return [Symbol] Current page numbering mode (:absolute or :dynamic)
      def page_numbering_mode
        get_config_value(:page_numbering_mode, DEFAULT_CONFIG[:page_numbering_mode])
      end

      # Update the page numbering mode
      #
      # @param mode [Symbol] New page numbering mode (:absolute or :dynamic)
      # @return [Boolean] True if updated successfully
      def update_page_numbering_mode(mode)
        validate_enum_value(:page_numbering_mode, mode, %i[absolute dynamic])
        update_config_value(:page_numbering_mode, mode)
      end

      # Get whether page numbers are shown
      #
      # @return [Boolean] True if page numbers should be shown
      def show_page_numbers?
        get_config_value(:show_page_numbers, DEFAULT_CONFIG[:show_page_numbers])
      end

      # Update whether to show page numbers
      #
      # @param show [Boolean] Whether to show page numbers
      # @return [Boolean] True if updated successfully
      def update_show_page_numbers(show)
        validate_boolean_value(:show_page_numbers, show)
        update_config_value(:show_page_numbers, show)
      end

      # Get the current line spacing
      #
      # @return [Symbol] Current line spacing (:compact, :normal, or :relaxed)
      def line_spacing
        raw = get_config_value(:line_spacing, DEFAULT_CONFIG[:line_spacing])
        normalized = normalize_line_spacing(raw)
        update_config_value(:line_spacing, normalized) if raw != normalized
        normalized
      end

      # Update the line spacing
      #
      # @param spacing [Symbol] New line spacing (:compact, :normal, or :relaxed)
      # @return [Boolean] True if updated successfully
      def update_line_spacing(spacing)
        normalized = normalize_line_spacing(spacing)
        validate_enum_value(:line_spacing, normalized, LINE_SPACING_ALLOWED)
        update_config_value(:line_spacing, normalized)
      end

      # Get the input debounce time in milliseconds
      #
      # @return [Integer] Input debounce time in milliseconds
      def input_debounce_ms
        get_config_value(:input_debounce_ms, DEFAULT_CONFIG[:input_debounce_ms])
      end

      # Update the input debounce time
      #
      # @param ms [Integer] New debounce time in milliseconds
      # @return [Boolean] True if updated successfully
      def update_input_debounce_ms(milliseconds)
        validate_positive_integer(:input_debounce_ms, milliseconds)
        update_config_value(:input_debounce_ms, milliseconds)
      end

      # Get all configuration as a hash
      #
      # @return [Hash] All configuration values
      def all_config
        config_state = @state_store.get(%i[config]) || {}
        DEFAULT_CONFIG.merge(config_state)
      end

      # Update multiple configuration values at once
      #
      # @param config_hash [Hash] Hash of configuration key-value pairs
      # @return [Boolean] True if updated successfully
      def update_multiple(config_hash)
        validate_required_params({ config_hash: config_hash }, [:config_hash])

        begin
          # Validate each value before applying any updates
          normalized = {}
          config_hash.each do |key, value|
            coerced = key == :line_spacing ? normalize_line_spacing(value) : value
            validate_config_key_value(key, coerced)
            normalized[key] = coerced
          end

          # Apply updates as a single state transaction
          @state_store.update(normalized.transform_keys { |k| [:config, k] })
          true
        rescue StandardError => e
          # Bubble up validation errors directly; wrap others
          raise e if e.is_a?(BaseRepository::ValidationError)

          handle_storage_error(e, 'updating multiple config values')
        end
      end

      # Reset configuration to defaults
      #
      # @return [Boolean] True if reset successfully
      def reset_to_defaults
        @state_store.update(DEFAULT_CONFIG.transform_keys { |k| [:config, k] })
        true
      rescue StandardError => e
        handle_storage_error(e, 'resetting configuration to defaults')
      end

      # Check if a configuration key has been customized from default
      #
      # @param key [Symbol] Configuration key to check
      # @return [Boolean] True if the value differs from default
      def customized?(key)
        current_value = get_config_value(key, nil)
        default_value = DEFAULT_CONFIG[key]
        current_value != default_value
      end

      private

      # Get a configuration value with fallback to default
      def get_config_value(key, default_value)
        value = @state_store.get([:config, key])
        value.nil? ? default_value : value
      rescue StandardError => e
        handle_storage_error(e, "getting config value #{key}")
      end

      # Update a single configuration value
      def update_config_value(key, value)
        stored_value = key == :line_spacing ? normalize_line_spacing(value) : value
        @state_store.update({ [:config, key] => stored_value })
        true
      rescue StandardError => e
        handle_storage_error(e, "updating config value #{key}")
      end

      # Validate that a value is one of the allowed enum values
      def validate_enum_value(key, value, allowed_values)
        return if allowed_values.include?(value)

        raise ValidationError,
              "Invalid #{key}: #{value}. Must be one of: #{allowed_values.join(', ')}"
      end

      # Validate that a value is a boolean
      def validate_boolean_value(key, value)
        return if value.is_a?(TrueClass) || value.is_a?(FalseClass)

        raise ValidationError, "Invalid #{key}: #{value}. Must be true or false"
      end

      # Validate that a value is a positive integer
      def validate_positive_integer(key, value)
        return if value.is_a?(Integer) && value.positive?

        raise ValidationError, "Invalid #{key}: #{value}. Must be a positive integer"
      end

      # Validate a specific config key-value pair
      def validate_config_key_value(key, value)
        case key
        when :view_mode
          validate_enum_value(key, value, %i[split single])
        when :page_numbering_mode
          validate_enum_value(key, value, %i[absolute dynamic])
        when :line_spacing
          normalized = normalize_line_spacing(value)
          validate_enum_value(key, normalized, LINE_SPACING_ALLOWED)
        when :show_page_numbers
          validate_boolean_value(key, value)
        when :input_debounce_ms, :search_highlight_timeout, :auto_save_interval
          validate_positive_integer(key, value)
        when :theme
          # Allow any symbol for theme for extensibility
          unless value.is_a?(Symbol)
            raise ValidationError,
                  "Invalid #{key}: #{value}. Must be a symbol"
          end
        else
          # Unknown keys are allowed for forward compatibility
          logger.debug("Unknown config key: #{key}")
        end
      end

      def normalize_line_spacing(value)
        sym = begin
          value.is_a?(String) ? value.downcase.to_sym : value&.to_sym
        rescue StandardError
          nil
        end
        LINE_SPACING_ALIASES.fetch(sym, sym || DEFAULT_CONFIG[:line_spacing])
      end
    end
  end
end
