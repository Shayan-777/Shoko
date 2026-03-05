# frozen_string_literal: true

module Shoko
  module Core
    module BookFormats
      module Epub
        # Scans document content for anchor and heading labels.
        class OPFNavigationDocumentScanner
          # Value object for extracted anchor and heading labels.
          ScanResult = Struct.new(:anchors, :headings)
          private_constant :ScanResult

          def initialize(cleaner:)
            @cleaner = cleaner
            @anchor_regex = %r{<(h[1-6])[^>]*?(?:id|name|xml:id)\s*=\s*["']([^"']+)["'][^>]*>(.*?)</\1>}im
            @heading_regex = %r{<(h[1-6])[^>]*>(.*?)</\1>}im
          end

          def scan(content)
            return ScanResult.new(anchors: {}, headings: []) unless content

            result = ScanResult.new(anchors: {}, headings: [])
            scan_anchors(content, result.anchors)
            scan_headings(content, result.headings)
            result
          end

          private

          def scan_anchors(content, anchors)
            content.scan(@anchor_regex) { |_tag, anchor, text| store_anchor(anchors, anchor, text) }
          end

          def scan_headings(content, headings)
            content.scan(@heading_regex) { |_tag, text| store_heading(headings, text) }
          end

          def store_anchor(anchors, anchor, text)
            label = @cleaner.clean_label(text)
            anchors[anchor] = label unless label.empty?
          end

          def store_heading(headings, text)
            label = @cleaner.clean_label(text)
            headings << label unless label.empty?
          end
        end
      end
    end
  end
end
