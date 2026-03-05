# frozen_string_literal: true

require_relative 'navigation_result'

module Shoko
  module Core
    module BookFormats
      module Epub
        # Chooses the best navigation source based on spine coverage.
        class OPFNavigationSelector
          # Value object for paired nav/NCX entries.
          EntryPair = Struct.new(:nav_entries, :ncx_entries)
          private_constant :EntryPair

          # Value object for availability of entries in each source.
          EntryAvailability = Struct.new(:nav_entries, :ncx_entries) do
            def selection
              nav_empty = nav_entries.empty?
              ncx_empty = ncx_entries.empty?
              if nav_empty && ncx_empty
                []
              elsif ncx_empty
                nav_entries
              elsif nav_empty
                ncx_entries
              end
            end
          end
          private_constant :EntryAvailability

          # Selects entries with fallback to spine coverage comparison.
          class EntrySelection
            def initialize(pair, spine_index)
              @pair = pair
              @availability = EntryAvailability.new(
                nav_entries: pair.nav_entries,
                ncx_entries: pair.ncx_entries
              )
              @coverage = SpineCoverage.new(spine_index)
            end

            def entries
              selection = @availability.selection
              return selection if selection

              @coverage.prefer(@pair.nav_entries, @pair.ncx_entries)
            end
          end

          # Computes spine coverage to decide between nav and NCX entries.
          class SpineCoverage
            def initialize(spine_index)
              @spine_index = spine_index
            end

            def prefer(nav_entries, ncx_entries)
              nav_score = score(nav_entries)
              ncx_score = score(ncx_entries)
              nav_score >= ncx_score ? nav_entries : ncx_entries
            end

            private

            def score(entries)
              entries.count do |entry|
                href = entry[:opf_href]
                href && @spine_index[href]
              end
            end
          end

          def initialize(opf:)
            @opf = opf
            @result_class = OPFNavigationResult
          end

          def choose(nav_bundle, ncx_bundle, manifest)
            pair = EntryPair.new(nav_entries: nav_bundle.toc_entries, ncx_entries: ncx_bundle.toc_entries)
            entries = EntrySelection.new(pair, build_spine_index(manifest)).entries
            return empty_result if entries.empty?

            titles = ncx_bundle.titles.merge(nav_bundle.titles)
            @result_class.new(toc_entries: entries, titles: titles)
          end

          private

          def empty_result
            @result_class.new(toc_entries: [], titles: {})
          end

          def build_spine_index(manifest)
            hrefs = {}
            @opf.elements.each('//spine/itemref') do |itemref|
              href = manifest[itemref.attributes['idref']]
              hrefs[href] = true if href
            end
            hrefs
          end
        end
      end
    end
  end
end
