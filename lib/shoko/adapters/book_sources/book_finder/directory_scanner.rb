# frozen_string_literal: true

require 'time'

require_relative '../../output/terminal/terminal_sanitizer'
require_relative '../../storage/config_paths'

module Shoko
  module Adapters::BookSources
    class EPUBFinder
      # Scans directories to locate EPUB files
      class DirectoryScanner
        def initialize(context)
          @context = context
        end

        def scan_all_directories
          all_dirs = build_directory_list
          warn_debug "Scanning directories: #{all_dirs.join(', ')}"

          all_dirs.each do |dir|
            break if @context.epubs.length >= EPUBFinder::MAX_FILES

            warn_debug "Scanning: #{dir}"
            scan_directory(dir)
          end
        end

        private

        def build_directory_list
          directories = priority_directories + other_directories
          directories.uniq.select { |dir| safe_directory_exists?(dir) }
        end

        def priority_directories
          [
            Adapters::Storage::ConfigPaths.downloads_root,
            '~/Books',
            '~/Bücher', # German books directory
            '~/Documents/Books',
            '~/Downloads',
            '~/Desktop',
            '~/Documents',
            '~/Library/Mobile Documents',
          ].map { |dir| File.expand_path(dir) }
        end

        def other_directories
          [
            '~',
            '~/Dropbox',
            '~/Google Drive',
            '~/OneDrive',
          ].map { |dir| File.expand_path(dir) }
        end

        def safe_directory_exists?(dir)
          Dir.exist?(dir)
        rescue StandardError
          false
        end

        def scan_directory(dir)
          return unless @context.can_scan?(dir, EPUBFinder::MAX_DEPTH, EPUBFinder::MAX_FILES)

          @context.mark_visited(dir)
          process_entries(dir)
        rescue Errno::EACCES, Errno::ENOENT, Errno::EPERM
          # Skip directories we can't access
        rescue StandardError => e
          warn_debug "Error scanning #{dir}: #{e.message}"
        end

        def process_entries(dir)
          Dir.entries(dir).each do |entry|
            next if entry.start_with?('.')

            path = File.join(dir, entry)
            next if @context.visited_paths.include?(path)

            process_path(path)
          end
        end

        def process_path(path)
          if File.directory?(path)
            process_directory(path)
          elsif epub_file?(path)
            add_epub(path)
          end
        rescue StandardError
          # Skip items we can't process
        end

        def process_directory(path)
          return if skip_directory?(path)

          DirectoryScanner.new(@context.with_deeper_depth).scan_directory(path)
        end

        def skip_directory?(path)
          base = File.basename(path).downcase
          EPUBFinder::SKIP_DIRS.map(&:downcase).include?(base)
        end

        def epub_file?(path)
          path.downcase.end_with?('.epub') &&
            File.readable?(path) &&
            File.size(path).positive?
        end

        def add_epub(path)
          raw_name = File.basename(path, '.epub').gsub(/[_-]/, ' ')
          display_name = Shoko::Adapters::Output::Terminal::TerminalSanitizer.sanitize(raw_name,
                                                                                       preserve_newlines: false, preserve_tabs: false)

          @context.epubs << {
            'path' => path,
            'name' => display_name,
            'size' => File.size(path),
            'modified' => File.mtime(path).iso8601,
            'dir' => File.dirname(path),
          }
        end

        def debug? = EPUBFinder::DEBUG_MODE

        def warn_debug(msg)
          warn msg if debug?
        end
      end
    end
  end
end
