# frozen_string_literal: true

require_relative 'navigation_document_scanner'

module Shoko
  module Core
    module BookFormats
      module Epub
        # Caches anchor labels and heading queues for navigation fallbacks.
        class OPFNavigationDocumentIndex
          # Value object for indexed document content.
          Document = Struct.new(:path, :content, keyword_init: true)
          private_constant :Document

          def initialize(entry_reader:, cleaner:)
            @entry_reader = entry_reader
            @scanner = OPFNavigationDocumentScanner.new(cleaner: cleaner)
            @anchors = {}
            @headings = {}
          end

          def anchor_label(path, anchor)
            ensure_index(path)
            @anchors[path][anchor]
          end

          def next_heading(path)
            ensure_index(path)
            queue = @headings[path]
            return '' unless queue

            queue.shift.to_s
          end

          def remove_heading(path, text)
            cleaned = text.to_s.strip
            return if cleaned.empty?

            queue = heading_queue(path)
            idx = queue&.index(cleaned)
            queue.delete_at(idx) if idx
          end

          private

          def ensure_index(path)
            return if @anchors.key?(path)

            content = @entry_reader.safe_read_entry(path)
            index_document(Document.new(path: path, content: content))
          end

          def index_document(document)
            path = document.path
            return if @anchors.key?(path)

            prepare_index(path)
            apply_scan(path, @scanner.scan(document.content))
          end

          def prepare_index(path)
            @anchors[path] = {}
            @headings[path] = []
          end

          def apply_scan(path, scan_result)
            @anchors[path].merge!(scan_result.anchors)
            @headings[path].concat(scan_result.headings)
          end

          def heading_queue(path)
            ensure_index(path)
            @headings[path]
          end
        end
      end
    end
  end
end
