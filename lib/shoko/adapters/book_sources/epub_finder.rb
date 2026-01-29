# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'
require 'timeout'

require_relative 'epub_finder/scanner_context'
require_relative 'epub_finder/directory_scanner'
require_relative '../storage/atomic_file_writer'
require_relative '../storage/config_paths'

module Shoko
  module Adapters::BookSources
    # EPUB file finder with robust error handling
    class EPUBFinder
      SCAN_TIMEOUT = 30
      MAX_DEPTH = 5
      MAX_FILES = 2000
      CACHE_DURATION = 86_400
      CONFIG_DIR = Adapters::Storage::ConfigPaths.config_root
      CACHE_FILE = File.join(CONFIG_DIR, 'epub_cache.json')
      DEBUG_MODE = ARGV.include?('--debug') || ENV.fetch('DEBUG', nil)
      SKIP_DIRS = %w[
        node_modules vendor cache tmp temp .git .svn
        __pycache__ build dist bin obj debug release
        .idea .vscode .atom .sublime frameworks
        applications system windows programdata appdata
        .Trash .npm .gem .bundle .cargo .rustup .cache
        .local .config
      ].freeze

      class << self
        def scan_system(force_refresh: false)
          cache = load_cache
          return cache['files'] if !force_refresh && cache_valid?(cache)

          scan_with_timeout
        end

        def clear_cache
          FileUtils.rm_f(CACHE_FILE)
        rescue StandardError
          nil
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

          Time.now - Time.parse(ts) >= CACHE_DURATION
        rescue StandardError
          true
        end

        def scan_with_timeout
          epubs = []
          epubs = perform_scan_with_timeout
        rescue Timeout::Error
          handle_timeout_error(epubs)
        rescue StandardError
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

          scanner = DirectoryScanner.new(context)
          scanner.scan_all_directories

          warn_debug "Found #{epubs.length} EPUB files"
          epubs
        end

        def load_cache
          return nil unless File.exist?(CACHE_FILE)

          parse_cache_file(CACHE_FILE)
        rescue StandardError => e
          warn_debug "Cache load error: #{e.message}"
          delete_cache_file(CACHE_FILE)
          nil
        end

        def parse_cache_file(path)
          data = File.read(path)
          json = JSON.parse(data)
          json if json.is_a?(Hash)
        end

        def delete_cache_file(path)
          File.delete(path)
        rescue StandardError
          nil
        end

        def save_cache(files)
          FileUtils.mkdir_p(File.dirname(CACHE_FILE))
          payload = JSON.pretty_generate({
                                           'timestamp' => Time.now.iso8601,
                                           'files' => files || [],
                                           'version' => VERSION,
                                         })
          Adapters::Storage::AtomicFileWriter.write(CACHE_FILE, payload)
        rescue StandardError => e
          warn_debug "Cache save error: #{e.message}"
        end

        def debug? = !!DEBUG_MODE

        def warn_debug(msg)
          warn msg if debug?
        end
      end
    end
  end
end
