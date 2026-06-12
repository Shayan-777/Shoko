# frozen_string_literal: true

require 'shoko/application/ports/outbound/formatting/display_line'

module Shoko
  module Application
    module Services
      module Pagination
        module Internal
          # Lazily hydrates page payloads against the active layout and document context.
          class PageHydrationFacade
            def initialize(page_hydrator:, pages_reader:, page_writer:, document_reader:, layout_context_reader:,
                           logger:)
              @page_hydrator = page_hydrator
              @pages_reader = pages_reader
              @page_writer = page_writer
              @document_reader = document_reader
              @layout_context_reader = layout_context_reader
              @logger = logger
            end

            def fetch(page_index, width: nil, height: nil)
              pages, index = resolve_page_request(page_index)
              return nil unless pages

              edge_page = resolve_edge_page(pages, index)
              return edge_page if edge_page

              page = pages[index]
              return page if formatted_lines?(page[:lines])

              hydrated = hydrate_page(page, width: width, height: height)
              @page_writer.call(index, hydrated) if hydrated
              hydrated
            rescue Shoko::Error => e
              @logger&.debug('page_hydrator.hydrate failed', page_index: page_index, error: e.message)
              page
            end

            private

            def resolve_page_request(page_index)
              pages = Array(@pages_reader.call)
              return [nil, nil] if pages.empty?

              [pages, page_index.to_i]
            end

            def resolve_edge_page(pages, index)
              return pages.first if index.negative?
              return pages.last if index >= pages.size

              nil
            end

            def hydrate_page(page, width:, height:)
              layout = @layout_context_reader.call(width: width, height: height)
              @page_hydrator.hydrate(
                page,
                @document_reader.call,
                width: layout[:width],
                height: layout[:height],
                prefer_formatting: true
              )
            end

            def formatted_lines?(lines)
              first = Array(lines).find { |line| !line.nil? }
              first.is_a?(Shoko::Application::Ports::Outbound::Formatting::DisplayLine)
            end
          end
        end
      end
    end
  end
end
