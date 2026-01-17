# frozen_string_literal: true

require_relative 'base_service'
require_relative 'navigation/context_builder'
require_relative 'navigation/absolute_change_applier'
require_relative 'navigation/absolute_layout'
require_relative 'navigation/dynamic_change_applier'
require_relative 'navigation/dynamic_strategy'
require_relative 'navigation/image_offset_snapper'
require_relative 'navigation/state_updater'
require_relative 'navigation/absolute_strategy'

module Shoko
  module Core
    module Services
      # Pure business logic for book navigation.
      # Replaces the coupled NavigationService with clean domain logic.
      class NavigationService < BaseService
        # Navigate to next page
        def next_page
          ctx = build_nav_context
          if dynamic_mode?(ctx)
            @dynamic_applier.apply(Navigation::DynamicStrategy.next_page(ctx))
          else
            @absolute_applier.apply(Navigation::AbsoluteStrategy.next_page(ctx))
          end
        end

        # Navigate to previous page
        def prev_page
          ctx = build_nav_context
          if dynamic_mode?(ctx)
            @dynamic_applier.apply(Navigation::DynamicStrategy.prev_page(ctx))
          else
            @absolute_applier.apply(Navigation::AbsoluteStrategy.prev_page(ctx))
          end
        end

        # Navigate to specific chapter
        #
        # @param chapter_index [Integer] Zero-based chapter index
        def jump_to_chapter(chapter_index)
          validate_chapter_index(chapter_index)
          ctx = build_nav_context
          if dynamic_mode?(ctx)
            page_index = @page_calculator.find_page_index(chapter_index, 0)
            page_index = 0 if page_index.nil? || page_index.negative?
            @state_updater.apply({ %i[reader current_chapter] => chapter_index,
                                   %i[reader current_page_index] => page_index })
          else
            @absolute_applier.apply(Navigation::AbsoluteStrategy.jump_to_chapter(ctx, chapter_index))
          end
        end

        # Navigate to beginning of book
        def go_to_start
          ctx = build_nav_context
          if dynamic_mode?(ctx)
            @dynamic_applier.apply(Navigation::DynamicStrategy.go_to_start(ctx))
          else
            @absolute_applier.apply(Navigation::AbsoluteStrategy.go_to_start(ctx))
          end
        end

        # Navigate to end of book
        def go_to_end
          ctx = build_nav_context
          if dynamic_mode?(ctx)
            @dynamic_applier.apply(Navigation::DynamicStrategy.go_to_end(ctx))
          else
            @absolute_applier.apply(Navigation::AbsoluteStrategy.go_to_end(ctx))
          end
        end

        # Scroll within current page/view
        #
        # @param direction [Symbol] :up or :down
        # @param lines [Integer] Number of lines to scroll
        def scroll(direction, lines = 1)
          ctx = build_nav_context
          if ctx.mode == :dynamic
            # No-op for dynamic; scrolling is page-based via next/prev
            return
          end

          changes = Navigation::AbsoluteStrategy.scroll(ctx, direction, lines)
          @absolute_applier.apply(changes)
        end

        protected

        def required_dependencies
          [:state_store]
        end

        def setup_service_dependencies
          @state_store = resolve(:state_store)
          @page_calculator = resolve(:page_calculator) if registered?(:page_calculator)
          @layout_service = resolve(:layout_service) if registered?(:layout_service)

          @state_updater = Navigation::StateUpdater.new(@state_store)
          @context_builder = Navigation::ContextBuilder.new(@state_store, @page_calculator)
          @absolute_layout = Navigation::AbsoluteLayout.new(state_store: @state_store, layout_service: @layout_service)

          formatting_service = resolve(:formatting_service) if registered?(:formatting_service)
          document = resolve(:document) if registered?(:document)
          @image_snapper = Navigation::ImageOffsetSnapper.new(
            state_store: @state_store,
            layout_service: @layout_service,
            formatting_service: formatting_service,
            document: document
          )

          @dynamic_applier = Navigation::DynamicChangeApplier.new(
            state_store: @state_store,
            page_calculator: @page_calculator,
            state_updater: @state_updater
          )
          @absolute_applier = Navigation::AbsoluteChangeApplier.new(
            state_updater: @state_updater,
            absolute_layout: @absolute_layout,
            image_snapper: @image_snapper,
            advance_callback: method(:jump_to_chapter)
          )
        end

        private

        def build_nav_context
          ctx = @context_builder.build
          @absolute_layout.populate_context(ctx)
          ctx
        end

        def dynamic_mode?(ctx)
          ctx.mode == :dynamic && @page_calculator
        end

        def validate_chapter_index(index)
          raise ArgumentError, 'Chapter index must be non-negative' if index.negative?

          current_state = @state_store.current_state
          total_chapters = current_state.dig(:reader, :total_chapters) || 0

          return unless index >= total_chapters

          raise ArgumentError, "Chapter index #{index} exceeds total chapters #{total_chapters}"
        end
      end
    end
  end
end
