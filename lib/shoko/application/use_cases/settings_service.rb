# frozen_string_literal: true

require 'fileutils'

require_relative '../state/actions/update_config_action'
require_relative '../selectors/config_selectors'

module Shoko
  module Application::UseCases
    # Centralises configuration toggles and cache maintenance for menu settings flows.
    class SettingsService
      WIPE_CACHE_MESSAGE = "All caches wiped. Use 'Find Book' to rescan"

      def initialize(state_store:, terminal_service:, cache_manager:, dictionary_availability:,
                     wrapping_service: nil, recent_files_repository: nil, dictionary_service: nil,
                     catalog_service: nil, logger: nil)
        @state_store = state_store
        @terminal_service = terminal_service
        @cache_manager = cache_manager
        @dictionary_availability = dictionary_availability
        @wrapping_service = wrapping_service
        @recent_repository = recent_files_repository
        @dictionary_service = dictionary_service
        @catalog_service_ref = catalog_service
        @logger = logger
      end

      # Toggle split/single view mode and persist the change.
      def toggle_view_mode
        current = Shoko::Application::Selectors::ConfigSelectors.view_mode(@state_store) || :split
        new_mode = current == :split ? :single : :split
        dispatch_config(view_mode: new_mode)
        new_mode
      end

      # Toggle whether page numbers are displayed.
      def toggle_page_numbers
        current = Shoko::Application::Selectors::ConfigSelectors.show_page_numbers(@state_store)
        dispatch_config(show_page_numbers: !current)
      end

      # Cycle through line spacing options (compact → normal → relaxed → ...).
      def cycle_line_spacing
        modes = Shoko::Core::Models::ReaderSettings::LINE_SPACING_VALUES
        current = Shoko::Application::Selectors::ConfigSelectors.line_spacing(@state_store) || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
        next_mode = modes[(modes.index(current) || 1) + 1] || modes.first
        dispatch_config(line_spacing: next_mode)
        next_mode
      end

      # Toggle quote highlighting preference.
      def toggle_highlight_quotes
        current = Shoko::Application::Selectors::ConfigSelectors.highlight_quotes(@state_store)
        dispatch_config(highlight_quotes: !current)
      end

      def toggle_dictionary_backend
        current = Shoko::Application::Selectors::ConfigSelectors.dictionary_backend(@state_store)
        backend_name = current.to_s.downcase
        auto_enabled = backend_name.empty? && dictionary_auto_available?
        new_backend = case backend_name
                      when 'sqlite'
                        :disabled
                      when 'disabled'
                        :sqlite
                      else
                        auto_enabled ? :disabled : :sqlite
                      end
        dispatch_config(dictionary_backend: new_backend)
        new_backend
      end

      def cycle_dictionary_pair
        pairs = available_dictionary_pairs
        source = Shoko::Application::Selectors::ConfigSelectors.dictionary_source_lang(@state_store)
        target = Shoko::Application::Selectors::ConfigSelectors.dictionary_target_lang(@state_store)

        auto = dictionary_auto_setting?(source)
        indexed_pairs = pairs.map { |pair| [pair[:source], pair[:target]] }
        current_index = auto ? -1 : indexed_pairs.index([source, target]) || -1
        next_index = (current_index + 1) % (indexed_pairs.length + 1)

        if next_index.zero?
          dispatch_config(dictionary_source_lang: 'auto')
          { source: 'auto', target: target }
        else
          next_pair = indexed_pairs[next_index - 1]
          dispatch_config(dictionary_source_lang: next_pair[0], dictionary_target_lang: next_pair[1])
          { source: next_pair[0], target: next_pair[1] }
        end
      end

      def toggle_kitty_images
        current = Shoko::Application::Selectors::ConfigSelectors.kitty_images(@state_store)
        dispatch_config(kitty_images: !current)
      end

      # Toggle dynamic/absolute page numbering mode.
      def toggle_page_numbering_mode
        current = Shoko::Application::Selectors::ConfigSelectors.page_numbering_mode(@state_store) || :dynamic
        next_mode = current == :absolute ? :dynamic : :absolute
        dispatch_config(page_numbering_mode: next_mode)
        next_mode
      end

      # Wipe cached EPUB data, recent file history, and wrapping caches.
      # Returns the status message applied to the catalog.
      def wipe_cache(catalog: nil)
        @cache_manager.clear_epub_cache
        remove_epub_cache_on_disk
        @recent_repository&.clear
        @wrapping_service&.clear_cache

        target_catalog = catalog || @catalog_service_ref
        if target_catalog
          target_catalog.update_entries([])
          target_catalog.scan_status = :idle
          target_catalog.scan_message = WIPE_CACHE_MESSAGE
        end

        WIPE_CACHE_MESSAGE
      end

      private

      def dispatch_config(payload)
        @state_store.dispatch(Shoko::Application::Actions::UpdateConfigAction.new(**payload))
        @state_store.save_config if @state_store.respond_to?(:save_config)
      end

      def available_dictionary_pairs
        pairs = @dictionary_service&.available_language_pairs || []
        pairs.filter_map do |pair|
          {
            source: pair[:source] || pair['source'],
            target: pair[:target] || pair['target'],
          }
        end.uniq.sort_by { |pair| [pair[:source].to_s, pair[:target].to_s] }
      rescue StandardError
        []
      end

      def dictionary_auto_setting?(value)
        return true if value.nil?

        str = value.to_s.strip
        str.empty? || str.casecmp('auto').zero?
      end

      def dictionary_auto_available?
        return false unless @dictionary_availability&.sqlite3_available?

        path = Shoko::Application::Selectors::ConfigSelectors.dictionary_path(@state_store)
        @dictionary_availability.databases_present?(path)
      rescue StandardError
        false
      end

      def remove_epub_cache_on_disk
        cache_root = @cache_manager.cache_root
        return unless cache_root && File.directory?(cache_root)

        cache_real = safe_realpath(cache_root)
        return unless cache_real

        FileUtils.rm_rf(cache_real)
      rescue StandardError
        nil
      end

      def safe_realpath(path)
        root_real = File.realpath(File.dirname(path))
        cache_real = File.realpath(path)
        return cache_real if cache_real.start_with?(root_real) && allowed_cache_dir?(File.basename(cache_real))

        nil
      rescue StandardError
        allowed_cache_dir?(File.basename(path)) ? path : nil
      end

      def allowed_cache_dir?(name)
        %w[shoko reader].include?(name)
      end
    end
  end
end
