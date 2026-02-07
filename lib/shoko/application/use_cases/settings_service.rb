# frozen_string_literal: true

require 'fileutils'

module Shoko
  module Application::UseCases
    # Centralises configuration toggles and cache maintenance for menu settings flows.
    class SettingsService
      WIPE_CACHE_MESSAGE = "All caches wiped. Use 'Find Book' to rescan"

      def initialize(config_reader:, state_writer:, terminal_service:, cache_manager:, dictionary_availability:,
                     wrapping_service: nil, recent_files_repository: nil, dictionary_service: nil,
                     catalog_service: nil, logger: nil)
        @config_reader = config_reader
        @state_writer = state_writer
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
        current = @config_reader.view_mode || :single
        new_mode = current == :split ? :single : :split
        dispatch_config(view_mode: new_mode)
        new_mode
      end

      # Toggle whether page numbers are displayed.
      def toggle_page_numbers
        current = @config_reader.show_page_numbers
        dispatch_config(show_page_numbers: !current)
      end

      # Cycle through line spacing options (compact -> normal -> relaxed -> ...).
      def cycle_line_spacing
        modes = Shoko::Core::Models::ReaderSettings::LINE_SPACING_VALUES
        current = @config_reader.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
        next_mode = modes[(modes.index(current) || 1) + 1] || modes.first
        dispatch_config(line_spacing: next_mode)
        next_mode
      end

      # Toggle quote highlighting preference.
      def toggle_highlight_quotes
        current = @config_reader.highlight_quotes
        dispatch_config(highlight_quotes: !current)
      end

      def toggle_dictionary_backend
        current = @config_reader.dictionary_backend
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
        source = @config_reader.dictionary_source_lang
        target = @config_reader.dictionary_target_lang

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
        current = @config_reader.kitty_images
        dispatch_config(kitty_images: !current)
      end

      # Toggle dynamic/absolute page numbering mode.
      def toggle_page_numbering_mode
        current = @config_reader.page_numbering_mode || :dynamic
        next_mode = current == :absolute ? :dynamic : :absolute
        dispatch_config(page_numbering_mode: next_mode)
        next_mode
      end

      # Wipe selected cached data and/or downloaded books.
      # Returns the status message applied to the catalog.
      def wipe_cache(catalog: nil, cached: nil, downloads: nil, nuke: nil,
                     annotations: nil, bookmarks: nil, progress: nil, config_file: nil)
        cached = cached.nil? ? true : !!cached
        downloads = !!downloads
        nuke = !!nuke
        dictionary = false
        annotations = !!annotations
        bookmarks = !!bookmarks
        progress = !!progress
        config_file = !!config_file

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
        if target_catalog
          target_catalog.update_entries([])
          target_catalog.scan_status = :idle
          target_catalog.scan_message = wipe_cache_message(cached: cached, downloads: downloads, nuke: nuke,
                                                           annotations: annotations, bookmarks: bookmarks,
                                                           progress: progress, config_file: config_file)
        end

        wipe_cache_message(cached: cached, downloads: downloads, nuke: nuke,
                           annotations: annotations, bookmarks: bookmarks,
                           progress: progress, config_file: config_file)
      end

      private

      def dispatch_config(**payload)
        @state_writer.update_config(**payload)
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

        path = @config_reader.dictionary_path
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

      def remove_downloads_on_disk
        downloads_root = Shoko::Adapters::Storage::ConfigPaths.downloads_root
        return unless downloads_root && File.directory?(downloads_root)

        downloads_real = safe_realpath_for(downloads_root, allowed_basenames: ['downloads'])
        return unless downloads_real

        FileUtils.rm_rf(downloads_real)
      rescue StandardError
        nil
      end

      def remove_dictionary_databases
        dict_path = dictionary_storage_path
        return unless dict_path && File.directory?(dict_path)

        dict_real = safe_realpath_for(dict_path)
        return unless dict_real

        FileUtils.rm_rf(dict_real)
      rescue StandardError
        nil
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

      def safe_realpath_for(path, allowed_basenames: nil)
        return nil unless path

        real = File.realpath(path)
        return nil if real == '/' || real == Dir.home
        return nil if allowed_basenames && !allowed_basenames.include?(File.basename(real))

        real
      rescue StandardError
        return nil unless File.exist?(path)

        real = File.expand_path(path)
        return nil if real == '/' || real == Dir.home
        return nil if allowed_basenames && !allowed_basenames.include?(File.basename(real))

        real
      end

      def dictionary_storage_path
        config_path = @config_reader.dictionary_path.to_s.strip
        return File.expand_path(config_path) unless config_path.empty?

        @dictionary_availability&.default_databases_path ||
          File.join(Dir.home, '.local', 'share', 'shoko', 'dictionaries')
      rescue StandardError
        File.join(Dir.home, '.local', 'share', 'shoko', 'dictionaries')
      end

      def remove_user_data_files(annotations:, bookmarks:, progress:, config_file:)
        config_root = Shoko::Adapters::Storage::ConfigPaths.config_root
        root_real = safe_realpath_for(config_root)
        return unless root_real

        files = {
          annotations: File.join(root_real, 'annotations.json'),
          bookmarks: File.join(root_real, 'bookmarks.json'),
          progress: File.join(root_real, 'progress.json'),
          config_file: File.join(root_real, 'config.json'),
        }

        FileUtils.rm_f(files[:annotations]) if annotations
        FileUtils.rm_f(files[:bookmarks]) if bookmarks
        FileUtils.rm_f(files[:progress]) if progress
        FileUtils.rm_f(files[:config_file]) if config_file
      rescue StandardError
        nil
      end
    end
  end
end
