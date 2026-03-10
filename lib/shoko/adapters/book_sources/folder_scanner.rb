# frozen_string_literal: true

require_relative '../../adapters/book_sources/format_registry'
require_relative '../../core/ports/outbound/folder_scanner'
require_relative 'book_file_probe'

module Shoko
  module Adapters
    module BookSources
      # Scans a user-selected directory and enumerates supported ebook files.
      class FolderScanner
        include Shoko::Core::Ports::Outbound::FolderScanner

        GROUP_BY_EXTENSION = {
          '.epub' => :epub,
          '.pdf' => :pdf,
          '.fb2' => :fb2,
          '.fb2.zip' => :fb2,
          '.mobi' => :kindle,
          '.azw' => :kindle,
          '.azw3' => :kindle,
          '.rtf' => :rtf,
        }.freeze

        def initialize(format_registry:, book_file_probe:)
          @format_registry = format_registry
          @book_file_probe = book_file_probe
        end

        def scan(directory_path, recursive: true, skip_hidden: true)
          root = File.expand_path(directory_path.to_s)
          return [] unless Dir.exist?(root)

          results = []
          scan_directory(root, recursive: recursive, skip_hidden: skip_hidden, results: results)
          results.sort_by { |entry| entry.path.to_s.downcase }
        end

        private

        def scan_directory(directory_path, recursive:, skip_hidden:, results:)
          entries = Dir.children(directory_path).sort
          entries.each do |entry_name|
            next if skip_hidden && hidden_entry?(entry_name)

            path = File.join(directory_path, entry_name)
            if File.directory?(path)
              next unless recursive
              next if File.symlink?(path)

              scan_directory(path, recursive: recursive, skip_hidden: skip_hidden, results: results)
            else
              candidate = build_candidate(path)
              results << candidate if candidate
            end
          end
        end

        def build_candidate(path)
          return nil unless @book_file_probe.book_file?(path)

          extension = detect_extension(path)
          return nil unless extension

          Shoko::Core::Ports::Outbound::FolderScanner::Entry.new(
            path: path,
            format_group: group_for_extension(extension),
            format_extension: extension
          )
        end

        def detect_extension(path)
          lower = path.to_s.downcase
          @format_registry.supported_extensions
                          .sort_by { |ext| -ext.length }
                          .find { |ext| lower.end_with?(ext) }
        end

        def group_for_extension(extension)
          GROUP_BY_EXTENSION[extension] || extension.delete_prefix('.').tr('.', '_').to_sym
        end

        def hidden_entry?(entry_name)
          entry_name.to_s.start_with?('.')
        end
      end
    end
  end
end
