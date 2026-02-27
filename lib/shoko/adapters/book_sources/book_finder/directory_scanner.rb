# frozen_string_literal: true

require 'time'

require_relative '../../../shared/text_sanitizer'
require_relative '../../../core/book_formats/format_registry'
require_relative '../book_file_probe'

module Shoko
  module Adapters
    module BookSources
      class BookFinder
        # Scans directories to locate EPUB files
        class DirectoryScanner
          def initialize(context, config_root:, book_file_probe: nil)
            @context = context
            @config_root = config_root
            @book_file_probe = book_file_probe || Shoko::Adapters::BookSources::BookFileProbe.new
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
            directories = priority_directories + other_directories
            directories.uniq.select { |dir| safe_directory_exists?(dir) }
          end

          def priority_directories
            [
              @config_root,
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
            return unless @context.can_scan?(dir, BookFinder::MAX_DEPTH, BookFinder::MAX_FILES)

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
            elsif ebook_file?(path)
              add_book(path)
            end
          rescue StandardError
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
            BookFinder::SKIP_DIRS.map(&:downcase).include?(base)
          end

          def ebook_file?(path)
            @book_file_probe.book_file?(path)
          end

          def add_book(path)
            raw_name = strip_ebook_extension(path).gsub(/[_-]/, ' ')
            display_name = Shoko::Shared::TextSanitizer.sanitize(raw_name,
                                                                    preserve_newlines: false, preserve_tabs: false)

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
            Shoko::Core::BookFormats::FormatRegistry.supported_extensions
                                                         .sort_by { |ext| -ext.length }
                                                         .each do |ext|
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
