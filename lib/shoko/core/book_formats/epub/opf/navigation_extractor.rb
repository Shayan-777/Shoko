# frozen_string_literal: true

require_relative 'navigation_source_locator'
require_relative 'navigation_selector'
require_relative 'navigation_traversal'
require_relative 'navigation_result'

module Shoko
  module Core::BookFormats::Epub
    # Coordinates extraction of navigation entries from nav/NCX sources.
    class OPFNavigationExtractor
      def initialize(opf:, entry_reader:)
        @source_locator = OPFNavigationSourceLocator.new(opf: opf, entry_reader: entry_reader)
        @traversal = OPFNavigationTraversal.new(entry_reader: entry_reader)
        @selector = OPFNavigationSelector.new(opf: opf)
        @result_class = OPFNavigationResult
      end

      def extract(manifest)
        nav_bundle = extract_from_nav
        ncx_bundle = extract_from_ncx(manifest)
        @selector.choose(nav_bundle, ncx_bundle, manifest)
      end

      private

      def extract_from_nav
        nav_path = @source_locator.nav_path
        return empty_result unless nav_path

        @traversal.from_nav_path(nav_path)
      end

      def extract_from_ncx(manifest)
        ncx_path = @source_locator.ncx_path(manifest)
        return empty_result unless ncx_path

        @traversal.from_ncx_path(ncx_path)
      end

      def empty_result
        @result_class.new(toc_entries: [], titles: {})
      end
    end
  end
end
