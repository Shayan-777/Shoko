# frozen_string_literal: true

require 'shoko/shared/terminal/mouse_button'
require_relative 'inline_link/link_hit_resolver'
require_relative 'inline_link/destination_resolver'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Resolves and applies in-book inline link clicks (for example footnote refs).
          class InlineLinkNavigator
            def initialize(coordinate_service:, rendered_content_reader:, reader_state_reader:, document_reader:,
                           state_controller:, anchor_resolver:, logger: nil)
              @state_controller = state_controller
              @logger = logger
              @link_hit_resolver = InlineLink::LinkHitResolver.new(
                coordinate_service: coordinate_service,
                rendered_content_reader: rendered_content_reader
              )
              @destination_resolver = InlineLink::DestinationResolver.new(
                reader_state_reader: reader_state_reader,
                document_reader: document_reader,
                anchor_resolver: anchor_resolver
              )
            end

            def navigate(event)
              context = navigation_context_for(event)
              return false unless context

              href = context.fetch(:href)
              entry = context.fetch(:entry)
              destination = @destination_resolver.destination_for(href, entry)
              return false unless destination

              @state_controller.jump_to_chapter_offset(destination[:chapter_index], destination[:line_offset])
              true
            rescue Shoko::Error, ArgumentError => e
              @logger&.debug('inline_link_navigator.navigate_failed', error: e.class.name, message: e.message)
              false
            end

            def link_hit_for_event(event)
              @link_hit_resolver.hit_for_event(event)
            rescue Shoko::Error, ArgumentError => e
              @logger&.debug(
                'inline_link_navigator.link_hit_for_event_failed',
                error: e.class.name,
                message: e.message
              )
              nil
            end

            private

            def navigation_context_for(event)
              return nil unless Shoko::Shared::Terminal::MouseButton.left_release?(event)

              @link_hit_resolver.context_for_event(event)
            end
          end
        end
      end
    end
  end
end
