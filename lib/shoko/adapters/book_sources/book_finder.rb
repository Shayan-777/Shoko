# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'
require 'timeout'

require_relative 'book_finder/scanner_context'
require_relative 'book_finder/directory_scanner'
module Shoko
  module Adapters
    module BookSources
      # Book file finder with robust error handling
      class BookFinder
        SCAN_TIMEOUT = 30
        MAX_DEPTH = 5
        MAX_FILES = 2000
        CACHE_DURATION = 86_400
        SKIP_DIRS = %w[
          node_modules vendor cache tmp temp .git .svn
          __pycache__ build dist bin obj debug release
          .idea .vscode .atom .sublime frameworks
          applications system windows programdata appdata
          .Trash .npm .gem .bundle .cargo .rustup .cache
          .local .config
        ].freeze

        DEBUG_MODE = false

        def initialize(cache_writer:, config_root:, logger: nil)
          @cache_writer = cache_writer
          @config_root = config_root
          @logger = logger
        end

        def config_dir
          root = @config_root.to_s
          raise Shoko::ConfigurationError, 'BookFinder requires config_root' if root.empty?

          root
        end

        def cache_file
          File.join(config_dir, 'epub_cache.json')
        end

        def scan_system(force_refresh: false)
          cache = load_cache
          return cache['files'] if !force_refresh && cache_valid?(cache)

          scan_with_timeout
        end

        def clear_cache
          FileUtils.rm_f(cache_file)
        end

        private

        def cached_files
          cache = load_cache
          return [] unless cache_valid?(cache)

          cache['files']
        end

        def cache_valid?(cache)
          return false unless cache.is_a?(Hash)

          files = cache['files']
          ts = cache['timestamp']
          files.is_a?(Array) && ts && !cache_expired?(ts)
        end

        def cache_expired?(timestamp = nil)
          ts = timestamp.to_s.strip
          return true if ts.empty?

          Time.now - Time.iso8601(ts) >= CACHE_DURATION
        rescue ArgumentError => e
          raise Shoko::FatalExternalInputError.new("Malformed cache timestamp: #{e.message}",
                                                   source: :book_finder_cache)
        end

        def scan_with_timeout
          epubs = []
          epubs = perform_scan_with_timeout
        rescue Timeout::Error
          handle_timeout_error(epubs)
        rescue Shoko::Error
          epubs = cached_files_fallback
        ensure
          save_and_return_epubs(epubs)
        end

        def perform_scan_with_timeout
          Timeout.timeout(SCAN_TIMEOUT) { perform_scan }
        end

        def handle_timeout_error(epubs)
          save_cache(epubs) unless epubs.empty?
          epubs
        end

        def save_and_return_epubs(epubs)
          save_cache(epubs)
          epubs
        end

        def cached_files_fallback
          cache = load_cache
          cache && cache['files'] ? cache['files'] : []
        end

        def perform_scan
          epubs = []
          context = ScannerContext.new(
            epubs: epubs,
            visited_paths: Set.new,
            depth: 0
          )

          scanner = DirectoryScanner.new(context, config_root: config_dir)
          scanner.scan_all_directories

          warn_debug "Found #{epubs.length} EPUB files"
          epubs
        end

        def load_cache
          return nil unless File.exist?(cache_file)

          parse_cache_file(cache_file)
        rescue Shoko::Error => e
          warn_debug "Cache load error: #{e.message}"
          delete_cache_file(cache_file)
          nil
        end

        def parse_cache_file(path)
          data = File.read(path)
          json = JSON.parse(data)
          json if json.is_a?(Hash)
        end

        def delete_cache_file(path)
          File.delete(path)
        end

        def save_cache(files)
          FileUtils.mkdir_p(File.dirname(cache_file))
          payload = JSON.pretty_generate({
                                           'timestamp' => Time.now.iso8601,
                                           'files' => files || [],
                                           'version' => VERSION,
                                         })
          raise Shoko::ConfigurationError, 'BookFinder requires cache_writer' unless @cache_writer

          @cache_writer.write(cache_file, payload)
        rescue Shoko::Error => e
          warn_debug "Cache save error: #{e.message}"
        end

        def warn_debug(msg)
          return unless DEBUG_MODE

          @logger&.debug('book_finder.debug', message: msg)
        rescue Shoko::Error
          warn msg
        end
      end
    end
  end
end
