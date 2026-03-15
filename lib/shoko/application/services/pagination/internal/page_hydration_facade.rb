# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        module Internal
          # Lazily hydrates page payloads against the active layout and document context.
          class PageHydrationFacade
            def initialize(page_hydrator:, pages_reader:, page_writer:, document_reader:, layout_context_reader:, logger:)
              @page_hydrator = page_hydrator
              @pages_reader = pages_reader
              @page_writer = page_writer
              @document_reader = document_reader
              @layout_context_reader = layout_context_reader
              @logger = logger
            end

            def fetch(page_index, width: nil, height: nil, sidebar_visible: nil)
              pages = Array(@pages_reader.call)
              return nil if pages.empty?

              index = page_index.to_i
              return pages.first if index.negative?
              return pages.last if index >= pages.size

              page = pages[index]
              return page if formatted_lines?(page[:lines])

              layout = @layout_context_reader.call(width: width, height: height, sidebar_visible: sidebar_visible)
              hydrated = @page_hydrator.hydrate(
                page,
                @document_reader.call,
                width: layout[:width],
                height: layout[:height],
                sidebar_visible: layout[:sidebar_visible],
                prefer_formatting: true
              )
              @page_writer.call(index, hydrated) if hydrated
              hydrated
            rescue Shoko::Error => e
              @logger&.debug('page_hydrator.hydrate failed', page_index: page_index, error: e.message)
              page
            end

            private

            def formatted_lines?(lines)
              first = Array(lines).find { |line| !line.nil? }
              first.is_a?(Shoko::Core::Models::DisplayLine)
            end
          end
        end
      end
    end
  end
end
