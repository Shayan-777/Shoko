# frozen_string_literal: true

require_relative '../base_command'
require_relative '../../../../core/ports/inbound/reader_command_contexts'
require_relative '../../../../core/ports/inbound/menu_command_contexts'

module Shoko
  module Application
    module UseCases
      module Commands
        module Shared
          # Shared annotation editor commands executed in reader and menu contexts.
          class AnnotationEditorCommand < Commands::BaseCommand
            SUPPORTED_INTENTS = %i[
              annotation_editor_backspace
              annotation_editor_cancel
              annotation_editor_enter
              annotation_editor_move_down
              annotation_editor_move_left
              annotation_editor_move_right
              annotation_editor_move_up
              annotation_editor_save
            ].freeze

            def self.registry
              SUPPORTED_INTENTS.to_h { |symbol| [symbol, -> { new(symbol) }] }.freeze
            end

            def initialize(intent_symbol)
              @intent_symbol = intent_symbol.to_sym
              super(
                name: "annotation_editor_#{@intent_symbol}",
                description: "Execute #{@intent_symbol}"
              )
            end

            def validate_context(context)
              super
              return if context.is_a?(Shoko::Core::Ports::Inbound::ReaderAnnotationEditorCommandContext)
              return if context.is_a?(Shoko::Core::Ports::Inbound::MenuAnnotationCommandContext)

              raise ValidationError.new(
                'Context must implement ReaderAnnotationEditorCommandContext or MenuAnnotationCommandContext',
                command_name: name
              )
            end

            protected

            def perform(context, _params = {})
              case @intent_symbol
              when :annotation_editor_backspace then context.annotation_editor_backspace
              when :annotation_editor_cancel then context.annotation_editor_cancel
              when :annotation_editor_enter then context.annotation_editor_enter
              when :annotation_editor_move_down then context.annotation_editor_move_down
              when :annotation_editor_move_left then context.annotation_editor_move_left
              when :annotation_editor_move_right then context.annotation_editor_move_right
              when :annotation_editor_move_up then context.annotation_editor_move_up
              when :annotation_editor_save then context.annotation_editor_save
              else
                raise ExecutionError.new("Unsupported shared annotation editor intent: #{@intent_symbol}", command_name: name)
              end

              @intent_symbol
            end
          end
        end
      end
    end
  end
end
