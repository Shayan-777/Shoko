# frozen_string_literal: true

require_relative 'settings_service/theme_settings'

module Shoko
  module Application
    module UseCases
      # Centralises configuration toggles and cache maintenance for menu settings flows.
      class SettingsService
        include SettingsServiceThemeSettings

        WIPE_CACHE_MESSAGE = "All caches wiped. Use 'Find Book' to rescan"

        def initialize(app_config_store:, cache_manager:, dictionary_availability:,
                       dictionary_storage:, data_cleanup:,
                       wrapping_service: nil, recent_files_repository: nil, dictionary_service: nil,
                       catalog_service: nil, config_storage: nil, logger: nil)
          @app_config_store = app_config_store
          @cache_manager = cache_manager
          @dictionary_availability = dictionary_availability
          @dictionary_storage = dictionary_storage
          @data_cleanup = data_cleanup
          @wrapping_service = wrapping_service
          @recent_repository = recent_files_repository
          @dictionary_service = dictionary_service
          @catalog_service_ref = catalog_service
          @config_storage = config_storage
          @logger = logger
        end

        # Toggle split/single view mode and persist the change.
        def toggle_view_mode
          current = current_config.view_mode || :single
          new_mode = current == :split ? :single : :split
          dispatch_config(view_mode: new_mode)
          new_mode
        end

        # Toggle whether page numbers are displayed.
        def toggle_page_numbers
          current = current_config.show_page_numbers
          dispatch_config(show_page_numbers: !current)
        end

        # Cycle through line spacing options (compact -> normal -> relaxed -> ...).
        def cycle_line_spacing
          modes = Shoko::Core::Models::ReaderSettings::LINE_SPACING_VALUES
          current = current_config.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
          next_mode = modes[(modes.index(current) || 1) + 1] || modes.first
          dispatch_config(line_spacing: next_mode)
          next_mode
        end

        # Toggle quote highlighting preference.
        def toggle_highlight_quotes
          current = current_config.highlight_quotes
          dispatch_config(highlight_quotes: !current)
        end

        def toggle_dictionary_backend
          current = current_config.dictionary_backend
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
          source = current_config.dictionary_source_lang
          target = current_config.dictionary_target_lang

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
          current = current_config.kitty_images
          dispatch_config(kitty_images: !current)
        end

        # Toggle dynamic/absolute page numbering mode.
        def toggle_page_numbering_mode
          current = current_config.page_numbering_mode || :dynamic
          next_mode = current == :absolute ? :dynamic : :absolute
          dispatch_config(page_numbering_mode: next_mode)
          next_mode
        end

        # Wipe selected cached data and/or downloaded books.
        # Returns the status message applied to the catalog.
        def wipe_cache(catalog: nil, cached: nil, downloads: nil, nuke: nil,
                       annotations: nil, bookmarks: nil, progress: nil, config_file: nil)
          cached = true if cached.nil?
          cached = !cached.nil? && cached != false
          downloads = !downloads.nil? && downloads != false
          nuke = !nuke.nil? && nuke != false
          dictionary = false
          annotations = !annotations.nil? && annotations != false
          bookmarks = !bookmarks.nil? && bookmarks != false
          progress = !progress.nil? && progress != false
          config_file = !config_file.nil? && config_file != false

          if nuke
            cached = true
            downloads = true
            dictionary = true
            annotations = true
            bookmarks = true
            progress = true
            config_file = true
          end

          wipe_cached_data if cached
          remove_downloads_on_disk if downloads
          remove_dictionary_databases if dictionary
          remove_user_data_files(annotations: annotations, bookmarks: bookmarks,
                                 progress: progress, config_file: config_file)

          target_catalog = catalog || @catalog_service_ref
          target_catalog&.reset_after_wipe(
            message: wipe_cache_message(cached: cached, downloads: downloads, nuke: nuke,
                                        annotations: annotations, bookmarks: bookmarks,
                                        progress: progress, config_file: config_file)
          )

          wipe_cache_message(cached: cached, downloads: downloads, nuke: nuke,
                             annotations: annotations, bookmarks: bookmarks,
                             progress: progress, config_file: config_file)
        end

        private

        def dispatch_config(**payload)
          @app_config_store.save(current_config.with(**payload))
        end

        def current_config
          @app_config_store.load
        end

        def available_dictionary_pairs
          pairs = @dictionary_service&.available_language_pairs || []
          pairs.filter_map do |pair|
            normalized = normalize_language_pair(pair)
            source = normalized[:source].to_s.strip
            target = normalized[:target].to_s.strip
            next if source.empty? || target.empty?

            { source: source, target: target }
          end.uniq.sort_by { |pair| [pair[:source].to_s, pair[:target].to_s] }
        end

        def dictionary_auto_setting?(value)
          return true if value.nil?

          str = value.to_s.strip
          str.empty? || str.casecmp('auto').zero?
        end

        def dictionary_auto_available?
          return false unless @dictionary_availability&.sqlite3_available?

          @dictionary_storage&.databases_present?(current_config.dictionary_path)
        end

        def remove_epub_cache_on_disk
          @data_cleanup&.remove_cache_root(@cache_manager.cache_root)
        end

        def remove_downloads_on_disk
          @data_cleanup&.remove_downloads_root(configured_config_root)
        end

        def remove_dictionary_databases
          @dictionary_storage&.remove_databases_path(current_config.dictionary_path)
        end

        def wipe_cached_data
          @cache_manager.clear_epub_cache
          remove_epub_cache_on_disk
          @recent_repository&.clear
          @wrapping_service&.clear_cache
        end

        def wipe_cache_message(cached:, downloads:, nuke:, annotations:, bookmarks:, progress:, config_file:)
          return "All data wiped. Use 'Find Book' to rescan" if nuke

          data = annotations || bookmarks || progress || config_file
          return "Caches + downloads + data wiped. Use 'Find Book' to rescan" if cached && downloads && data
          return "Caches + downloads wiped. Use 'Find Book' to rescan" if cached && downloads
          return "Caches + data wiped. Use 'Find Book' to rescan" if cached && data
          return "Downloads + data wiped. Use 'Find Book' to rescan" if downloads && data
          return WIPE_CACHE_MESSAGE if cached
          return "Downloads deleted. Use 'Find Book' to rescan" if downloads
          return 'User data wiped.' if data

          'Nothing selected to wipe'
        end

        def remove_user_data_files(annotations:, bookmarks:, progress:, config_file:)
          @data_cleanup&.remove_user_data_files(
            config_root: configured_config_root,
            annotations: annotations,
            bookmarks: bookmarks,
            progress: progress,
            config_file: config_file
          )
        end

        def configured_config_root
          @config_storage&.config_dir
        end

        def normalize_language_pair(pair)
          raise ArgumentError, "dictionary language pair must be a Hash, got #{pair.class}" unless pair.is_a?(Hash)

          pair.each_with_object({}) do |(key, value), acc|
            normalized_key = key.is_a?(String) ? key.to_sym : key
            acc[normalized_key] = value
          end
        end
      end
    end
  end
end
