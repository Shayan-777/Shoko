# frozen_string_literal: true

require_relative 'base_command'

module Shoko
  module Application
    module Commands
      # Commands for driving the Annotation Editor screen via a clean, public API.
      class AnnotationEditorCommand < BaseCommand
        def initialize(action, name: nil, description: nil)
          @action = action
          super(
            name: name || "annotation_editor_#{action}",
            description: description || "Annotation editor #{action.to_s.tr('_', ' ')}"
          )
        end

        protected

        def perform(context, params = {})
          ctx = build_editor_context(context)
          dispatch_action(ctx, params)
        end

        EditorContext = Data.define(:ui_controller, :mode, :state)
        private_constant :EditorContext

        private

        def build_editor_context(context)
          ui_ctrl = context.respond_to?(:ui_controller) ? context.ui_controller : nil
          mode = if context.respond_to?(:current_editor_component)
                   context.current_editor_component
                 else
                   ui_ctrl&.current_mode
                 end
          EditorContext.new(ui_controller: ui_ctrl, mode: mode, state: context.state)
        end

        def dispatch_action(ctx, params)
          case @action
          when :save then handle_save(ctx)
          when :cancel then handle_cancel(ctx)
          when :backspace then handle_simple_action(ctx, :handle_backspace)
          when :enter then handle_simple_action(ctx, :handle_enter)
          when :insert_char then handle_insert_char(ctx, params)
          else :pass
          end
        end

        def handle_save(ctx)
          dispatch_to_mode(ctx.mode, :save_annotation)
          :handled
        end

        def handle_cancel(ctx)
          return :handled if dispatch_to_mode(ctx.mode, :cancel_annotation)

          cancel_via_ui(ctx.ui_controller) || cancel_via_menu(ctx.state)
          :handled
        end

        def cancel_via_ui(ui_ctrl)
          return false unless ui_ctrl

          begin
            ui_ctrl.cleanup_popup_state
          rescue StandardError
            # no-op
          end
          begin
            ui_ctrl.switch_mode(:read)
          rescue StandardError
            # fall through
          end
          true
        end

        def cancel_via_menu(state)
          state&.dispatch(Shoko::Application::Actions::UpdateMenuAction.new(mode: :annotations))
        rescue StandardError
          # best-effort
        end

        def handle_simple_action(ctx, method_name)
          dispatch_to_mode(ctx.mode, method_name)
          :handled
        end

        def handle_insert_char(ctx, params)
          char = (params[:key] || '').to_s
          return :pass if char.empty?

          dispatch_to_mode(ctx.mode, :handle_character, char)
          :handled
        end

        def dispatch_to_mode(mode, method_name, *)
          return false unless mode.respond_to?(method_name)

          mode.public_send(method_name, *)
          true
        end
      end

      # Factory methods for building AnnotationEditor commands.
      module AnnotationEditorCommandFactory
        def self.save
          AnnotationEditorCommand.new(:save)
        end

        def self.cancel
          AnnotationEditorCommand.new(:cancel)
        end

        def self.backspace
          AnnotationEditorCommand.new(:backspace)
        end

        def self.enter
          AnnotationEditorCommand.new(:enter)
        end

        # The char parameter is accepted for API compatibility with CommandPortAdapter
        # but intentionally unused — the actual character is read from params[:key]
        # at execution time in handle_insert_char.
        def self.insert_char(_char = nil)
          AnnotationEditorCommand.new(:insert_char)
        end
      end
    end
  end
end
