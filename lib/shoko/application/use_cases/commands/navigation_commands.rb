# frozen_string_literal: true

require_relative 'base_command'
require_relative '../../../core/ports/inbound/reader_navigation_command_context'

module Shoko
  module Application
    module UseCases
      module Commands
        # Navigation commands using proper domain services.
        # Eliminates direct controller coupling and state manipulation.
        class NavigationCommand < BaseCommand
          def initialize(action, name: nil, description: nil)
            @action = action
            super(
              name: name || "navigate_#{action}",
              description: description || "Navigate #{humanize_action(action)}"
            )
          end

          def validate_context(context)
            super
            return if context.is_a?(Shoko::Core::Ports::Inbound::ReaderNavigationCommandContext)

            raise ValidationError.new(
              'Context must implement Core::Ports::Inbound::ReaderNavigationCommandContext',
              command_name: name
            )
          end

          protected

          def perform(context, _params = {})
            navigation_service = context.navigation_service
            current_chapter = current_chapter_from(context.reader_state_reader)

            case @action
            when :next_page
              navigation_service.next_page
            when :prev_page
              navigation_service.prev_page
            when :next_chapter
              navigation_service.jump_to_chapter(current_chapter + 1)
            when :prev_chapter
              navigation_service.jump_to_chapter([current_chapter - 1, 0].max)
            when :go_to_start
              navigation_service.go_to_start
            when :go_to_end
              navigation_service.go_to_end
            else
              raise ExecutionError.new("Unknown navigation action: #{@action}", command_name: name)
            end

            @action
          end

          private

          def humanize_action(action)
            action.to_s.tr('_', ' ')
          end

          def current_chapter_from(reader_state_reader)
            return 0 unless reader_state_reader

            reader_state_reader.current_chapter || 0
          rescue StandardError
            0
          end
        end

        # Command that scrolls within the current chapter by a number of lines.
        class ScrollCommand < BaseCommand
          def initialize(direction, lines: 1, name: nil, description: nil)
            @direction = direction
            @lines = lines
            super(
              name: name || "scroll_#{direction}",
              description: description || "Scroll #{direction} #{lines} line(s)"
            )
          end

          def validate_context(context)
            super
            return if context.is_a?(Shoko::Core::Ports::Inbound::ReaderNavigationCommandContext)

            raise ValidationError.new(
              'Context must implement Core::Ports::Inbound::ReaderNavigationCommandContext',
              command_name: name
            )
          end

          def validate_parameters(params)
            super

            valid_directions = %i[up down]
            unless valid_directions.include?(@direction)
              raise ValidationError.new("Direction must be one of #{valid_directions}",
                                        command_name: name)
            end

            return if @lines.is_a?(Integer) && @lines.positive?

            raise ValidationError.new('Lines must be a positive integer', command_name: name)
          end

          protected

          def perform(context, _params = {})
            context.navigation_service.scroll(@direction, @lines)

            { direction: @direction, lines: @lines }
          end
        end

        # Command that jumps to a specific chapter index.
        class JumpToChapterCommand < BaseCommand
          def initialize(chapter_index = nil, name: nil, description: nil)
            @chapter_index = chapter_index
            super(
              name: name || 'jump_to_chapter',
              description: description || 'Jump to specific chapter'
            )
          end

          def validate_context(context)
            super
            return if context.is_a?(Shoko::Core::Ports::Inbound::ReaderNavigationCommandContext)

            raise ValidationError.new(
              'Context must implement Core::Ports::Inbound::ReaderNavigationCommandContext',
              command_name: name
            )
          end

          def validate_parameters(params)
            super

            # Chapter index can come from params or constructor
            index = params[:chapter_index] || @chapter_index

            return if index.is_a?(Integer) && index >= 0

            raise ValidationError.new('Chapter index must be a non-negative integer',
                                      command_name: name)
          end

          protected

          def perform(context, params = {})
            index = params[:chapter_index] || @chapter_index
            context.navigation_service.jump_to_chapter(index)

            { chapter_index: index }
          end
        end

        # Factory methods for common navigation commands
        module NavigationCommandFactory
          def self.next_page
            NavigationCommand.new(:next_page)
          end

          def self.prev_page
            NavigationCommand.new(:prev_page)
          end

          def self.next_chapter
            NavigationCommand.new(:next_chapter)
          end

          def self.prev_chapter
            NavigationCommand.new(:prev_chapter)
          end

          def self.go_to_start
            NavigationCommand.new(:go_to_start)
          end

          def self.go_to_end
            NavigationCommand.new(:go_to_end)
          end

          def self.scroll_up(lines = 1)
            ScrollCommand.new(:up, lines: lines)
          end

          def self.scroll_down(lines = 1)
            ScrollCommand.new(:down, lines: lines)
          end

          def self.jump_to_chapter(index)
            JumpToChapterCommand.new(index)
          end
        end
      end
    end
  end
end
