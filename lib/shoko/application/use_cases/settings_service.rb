# frozen_string_literal: true

require_relative 'settings_service/wipe_cache_plan'
require_relative 'settings_service/wipe_cache_message_builder'
require_relative '../../core/models/reader_settings'
require_relative '../../shared/download_source_policy'
require_relative '../../shared/theme_policy'

module Shoko
  module Application
    module UseCases
      # Centralises configuration toggles and cache maintenance for menu settings flows.
      class SettingsService
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

        def toggle_view_mode
          current = current_config.view_mode || :single
          new_mode = current == :split ? :single : :split
          dispatch_config(view_mode: new_mode)
          new_mode
        end

        def toggle_page_numbers
          current = current_config.show_page_numbers
          dispatch_config(show_page_numbers: !current)
        end

        def cycle_line_spacing
          modes = Shoko::Core::Models::ReaderSettings::LINE_SPACING_VALUES
          current = current_config.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
          next_mode = modes[(modes.index(current) || 1) + 1] || modes.first
          dispatch_config(line_spacing: next_mode)
          next_mode
        end

        def cycle_download_source
          sources = Shoko::Shared::DownloadSourcePolicy.canonical_ids
          current = Shoko::Shared::DownloadSourcePolicy.normalize(current_config.download_source) ||
                    Shoko::Shared::DownloadSourcePolicy.default_id
          next_source = sources[(sources.index(current) || 0) + 1] || sources.first
          dispatch_config(download_source: next_source)
          next_source
        end

        def select_download_source(source)
          normalized = Shoko::Shared::DownloadSourcePolicy.normalize(source)
          raise ArgumentError, "Unsupported download source: #{source.inspect}" unless normalized

          dispatch_config(download_source: normalized)
          normalized
        end

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
          pairs = available_dictionary_pairs.map { |pair| [pair[:source], pair[:target]] }
          next_pair = next_dictionary_pair(
            pairs,
            current_config.dictionary_source_lang,
            current_config.dictionary_target_lang
          )
          apply_dictionary_pair(next_pair)
        end

        def toggle_kitty_images
          current = current_config.kitty_images
          dispatch_config(kitty_images: !current)
        end

        def cycle_paragraph_style
          modes = Shoko::Core::Models::ReaderSettings::PARAGRAPH_STYLE_VALUES
          current = current_config.paragraph_style || Shoko::Core::Models::ReaderSettings::DEFAULT_PARAGRAPH_STYLE
          next_mode = modes[(modes.index(current) || 0) + 1] || modes.first
          dispatch_config(paragraph_style: next_mode)
          next_mode
        end

        def cycle_justify
          modes = Shoko::Core::Models::ReaderSettings::JUSTIFY_VALUES
          current = current_config.justify || Shoko::Core::Models::ReaderSettings::DEFAULT_JUSTIFY
          next_mode = modes[(modes.index(current) || 0) + 1] || modes.first
          dispatch_config(justify: next_mode)
          next_mode
        end

        def toggle_book_colors
          current = current_config.book_colors
          dispatch_config(book_colors: current == false)
        end

        def toggle_page_numbering_mode
          current = current_config.page_numbering_mode || :dynamic
          next_mode = current == :absolute ? :dynamic : :absolute
          dispatch_config(page_numbering_mode: next_mode)
          next_mode
        end

        def toggle_prepaginate_on_resize
          current = current_config.prepaginate_on_resize
          dispatch_config(prepaginate_on_resize: !current)
        end

        def wipe_cache(catalog: nil, cached: nil, downloads: nil, dictionary: nil, nuke: nil,
                       annotations: nil, bookmarks: nil, progress: nil, config_file: nil)
          plan = SettingsServiceWipeCachePlan.build(
            cached: cached,
            downloads: downloads,
            dictionary: dictionary,
            nuke: nuke,
            annotations: annotations,
            bookmarks: bookmarks,
            progress: progress,
            config_file: config_file
          )
          execute_wipe_cache(plan)
          message = SettingsServiceWipeCacheMessageBuilder.build(plan)
          (catalog || @catalog_service_ref)&.reset_after_wipe(message: message)
          message
        end

        # Cycle through canonical reader theme options and persist the change.
        def cycle_theme
          themes = Shoko::Shared::ThemePolicy.canonical_ids
          current = Shoko::Shared::ThemePolicy.normalize(@app_config_store.load.theme) ||
                    Shoko::Shared::ThemePolicy.default_id
          current_index = themes.index(current) || 0
          next_theme = themes[(current_index + 1) % themes.length]
          dispatch_config(theme: next_theme)
          next_theme
        end

        # Set explicit theme after validating against canonical theme registry.
        # rubocop:disable Naming/AccessorMethodName
        def set_theme(theme_id)
          canonical = Shoko::Shared::ThemePolicy.normalize(theme_id)
          raise ArgumentError, "Unsupported theme: #{theme_id.inspect}" unless canonical

          dispatch_config(theme: canonical)
          canonical
        end
        # rubocop:enable Naming/AccessorMethodName

        private

        def dispatch_config(**payload)
          @app_config_store.save(current_config.with(**payload))
        end

        def current_config = @app_config_store.load

        def available_dictionary_pairs
          Array(@dictionary_service&.available_language_pairs)
            .filter_map { |pair| normalized_dictionary_pair(pair) }
            .uniq
            .sort_by { |pair| [pair[:source].to_s, pair[:target].to_s] }
        end

        def normalized_dictionary_pair(pair)
          normalized = normalize_language_pair(pair)
          source = normalized_language_value(normalized[:source])
          target = normalized_language_value(normalized[:target])
          return nil unless source && target

          { source: source, target: target }
        end

        def normalized_language_value(value)
          str = value.to_s.strip
          str.empty? ? nil : str
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

        def remove_user_data_files(annotations:, bookmarks:, progress:, config_file:)
          @data_cleanup&.remove_user_data_files(
            config_root: configured_config_root,
            annotations: annotations,
            bookmarks: bookmarks,
            progress: progress,
            config_file: config_file
          )
        end

        def configured_config_root = @config_storage&.config_dir

        def next_dictionary_pair(pairs, source, target)
          current_index = current_dictionary_pair_index(pairs, source, target)
          next_index = (current_index + 1) % (pairs.length + 1)
          return { source: 'auto', target: target } if next_index.zero?

          next_source, next_target = pairs.fetch(next_index - 1)
          { source: next_source, target: next_target }
        end

        def current_dictionary_pair_index(pairs, source, target)
          return -1 if dictionary_auto_setting?(source)

          pairs.index([source, target]) || -1
        end

        def apply_dictionary_pair(pair)
          if dictionary_auto_setting?(pair[:source])
            dispatch_config(dictionary_source_lang: 'auto')
          else
            dispatch_config(dictionary_source_lang: pair[:source], dictionary_target_lang: pair[:target])
          end
          pair
        end

        def execute_wipe_cache(plan)
          wipe_cached_data if plan.cached
          remove_downloads_on_disk if plan.downloads
          remove_dictionary_databases if plan.dictionary
          remove_user_data_files(
            annotations: plan.annotations,
            bookmarks: plan.bookmarks,
            progress: plan.progress,
            config_file: plan.config_file
          )
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
