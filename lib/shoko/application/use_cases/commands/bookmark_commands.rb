# frozen_string_literal: true

require_relative 'base_command'
require_relative '../../../core/ports/inbound/reader_bookmark_command_context'

module Shoko
  module Application
    module UseCases
      module Commands
        # Bookmark management commands using domain services.
        class BookmarkCommand < BaseCommand
          def initialize(action, name: nil, description: nil)
            @action = action
            super(
              name: name || "bookmark_#{action}",
              description: description || "Bookmark #{action.to_s.tr('_', ' ')}"
            )
          end

          def validate_context(context)
            super
            return if context.is_a?(Shoko::Core::Ports::Inbound::ReaderBookmarkCommandContext)

            raise ValidationError.new(
              'Context must implement Core::Ports::Inbound::ReaderBookmarkCommandContext',
              command_name: name
            )
          end

          protected

          def perform(context, params = {})
            bookmark_service = context.bookmark_service

            case @action
            when :add
              handle_add_bookmark(bookmark_service, params)
            when :remove
              handle_remove_bookmark(bookmark_service, params)
            when :toggle
              handle_toggle_bookmark(bookmark_service, params)
            when :jump_to
              handle_jump_to_bookmark(bookmark_service, params)
            else
              raise ExecutionError.new("Unknown bookmark action: #{@action}", command_name: name)
            end

            @action
          end

          private

          def handle_add_bookmark(service, params)
            text_snippet = params[:text_snippet]
            service.add_bookmark(text_snippet)
          end

          def handle_remove_bookmark(service, params)
            bookmark = params[:bookmark]

            raise ValidationError.new('Bookmark required for remove action', command_name: name) unless bookmark

            service.remove_bookmark(bookmark)
          end

          def handle_toggle_bookmark(service, params)
            text_snippet = params[:text_snippet]
            result = service.toggle_bookmark(text_snippet)

            { result: result }
          end

          def handle_jump_to_bookmark(service, params)
            bookmark = params[:bookmark]

            raise ValidationError.new('Bookmark required for jump_to action', command_name: name) unless bookmark

            service.jump_to_bookmark(bookmark)
          end
        end

        # Factory methods for bookmark commands
        module BookmarkCommandFactory
          def self.add_bookmark(text_snippet = nil)
            command = BookmarkCommand.new(:add)

            # If text_snippet provided, create a wrapper that includes it in params
            if text_snippet
              lambda do |context, params = {}|
                command.execute(context, params.merge(text_snippet: text_snippet))
              end
            else
              command
            end
          end
        end
      end
    end
  end
end
