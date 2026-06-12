# frozen_string_literal: true

require 'time'

require 'shoko/shared/text_sanitizer'
require 'shoko/adapters/book_sources/format_registry'
require_relative '../book_file_probe'

module Shoko
  module Adapters
    module BookSources
      class BookFinder
        # Scans directories to locate EPUB files
        class DirectoryScanner
          class << self
            def skip_dirs_downcased
              @skip_dirs_downcased ||= BookFinder::SKIP_DIRS.map(&:downcase).freeze
            end

            def supported_extensions_by_length
              extensions = Shoko::Adapters::BookSources::FormatRegistry.supported_extensions
              @supported_extensions_by_length ||= extensions.sort_by { |ext| -ext.length }.freeze
            end
          end

          def initialize(context, config_root:, book_file_probe:)
            @context = context
            @config_root = config_root
            @book_file_probe = book_file_probe
          end

          def scan_all_directories
            all_dirs = build_directory_list
            warn_debug "Scanning directories: #{all_dirs.join(', ')}"

            all_dirs.each do |dir|
              break if @context.epubs.length >= BookFinder::MAX_FILES

              warn_debug "Scanning: #{dir}"
              scan_directory(dir)
            end
          end

          private

          def build_directory_list
            directories = configured_directories + default_directories
            directories.uniq.select { |dir| safe_directory_exists?(dir) }
          end

          def default_directories
            [
              File.join(@config_root, 'downloads'),
              '~/Books',
              '~/Bücher', # German books directory
              '~/Documents/Books',
            ].map { |dir| File.expand_path(dir) }
          end

          def configured_directories
            raw = ENV.fetch('SHOKO_BOOK_SCAN_DIRS', '').to_s
            return [] if raw.strip.empty?

            raw
              .split(File::PATH_SEPARATOR)
              .map(&:strip)
              .reject(&:empty?)
              .map { |dir| File.expand_path(dir) }
          end

          def safe_directory_exists?(dir)
            Dir.exist?(dir)
          end

          def scan_directory(dir)
            return unless @context.can_scan?(dir, BookFinder::MAX_DEPTH, BookFinder::MAX_FILES)

            @context.mark_visited(dir)
            process_entries(dir)
          rescue Errno::EACCES, Errno::ENOENT, Errno::EPERM
            # Skip directories we can't access
          rescue Shoko::Error => e
            warn_debug "Error scanning #{dir}: #{e.message}"
          end
          protected :scan_directory

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
            elsif ebook_file?(path)
              add_book(path)
            end
          rescue Shoko::Error
            # Skip items we can't process
          end

          def process_directory(path)
            return if skip_directory?(path)

            DirectoryScanner.new(
              @context.with_deeper_depth,
              config_root: @config_root,
              book_file_probe: @book_file_probe
            ).scan_directory(path)
          end

          def skip_directory?(path)
            base = File.basename(path).downcase
            self.class.skip_dirs_downcased.include?(base)
          end

          def ebook_file?(path)
            @book_file_probe.book_file?(path)
          end

          def add_book(path)
            raw_name = strip_ebook_extension(path).gsub(/[_-]/, ' ')
            display_name = Shoko::Shared::TextSanitizer.sanitize(raw_name,
                                                                 preserve_newlines: false,
                                                                 preserve_tabs: false)

            @context.epubs << {
              'path' => path,
              'name' => display_name,
              'size' => File.size(path),
              'modified' => File.mtime(path).iso8601,
              'dir' => File.dirname(path),
            }
          end

          def strip_ebook_extension(path)
            basename = File.basename(path)
            # Try compound extensions first (e.g. '.fb2.zip')
            self.class.supported_extensions_by_length.each do |ext|
              return basename[0..-(ext.length + 1)] if basename.downcase.end_with?(ext)
            end
            File.basename(path, File.extname(path))
          end

          def debug? = BookFinder::DEBUG_MODE

          def warn_debug(msg)
            warn msg if debug?
          end
        end
      end
    end
  end
end
