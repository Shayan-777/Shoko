# frozen_string_literal: true

require_relative '../../../adapters/runtime/session_state/rendered_content_reader_adapter'
require_relative '../../../adapters/ui/sessions/dictionary_ui_session_adapter'
require_relative '../../../adapters/ui/sessions/in_book_search_ui_session_adapter'
require_relative '../../../adapters/ui/sessions/annotation_overlay_ui_session_adapter'
require_relative '../../../adapters/ui/sessions/annotation_editor_launcher_adapter'
require_relative '../../../adapters/runtime/session_state/observer_registry_adapter'
require_relative '../../../adapters/runtime/session_state/render_state_writer_adapter'
require_relative '../../../adapters/runtime/session_state/notification_writer_adapter'
require_relative '../../../adapters/ui/view_models/reader_view_model_builder'

module Shoko
  module Composition
    module ContainerFactory
      # Registers UI session adapters and render-state writers for reader runtime state.
      module PortAndRepositoryRegistrationUiStateAdapters
        private

        def register_reader_ui_adapters(container)
          register_rendered_content_adapter(container)
          register_overlay_ui_sessions(container)
          register_annotation_ui_adapters(container)
        end

        def register_rendered_content_adapter(container)
          container.register_factory(:rendered_content_reader) do |c|
            Shoko::Adapters::Runtime::SessionState::RenderedContentReaderAdapter.new(
              c.resolve(:global_state),
              render_registry: c.resolve(:render_registry)
            )
          end
        end

        def register_overlay_ui_sessions(container)
          register_dictionary_ui_session(container)
          register_in_book_search_ui_session(container)
        end

        def register_dictionary_ui_session(container)
          container.register_factory(:dictionary_ui_session) do |c|
            Shoko::Adapters::Ui::Sessions::DictionaryUiSessionAdapter.new(
              reader_state_reader: c.resolve(:reader_state_reader),
              reader_session_mutator: c.resolve(:reader_session_mutator),
              ui_component_factory: c.resolve(:ui_component_factory),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_in_book_search_ui_session(container)
          container.register_factory(:in_book_search_ui_session) do |c|
            Shoko::Adapters::Ui::Sessions::InBookSearchUiSessionAdapter.new(
              reader_state_reader: c.resolve(:reader_state_reader),
              reader_session_mutator: c.resolve(:reader_session_mutator),
              ui_component_factory: c.resolve(:ui_component_factory),
              rendered_content_reader: c.resolve(:rendered_content_reader),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_annotation_ui_adapters(container)
          register_annotation_overlay_ui_session(container)
          register_annotation_editor_launcher(container)
        end

        def register_annotation_overlay_ui_session(container)
          container.register_factory(:annotation_overlay_ui_session) do |c|
            Shoko::Adapters::Ui::Sessions::AnnotationOverlayUiSessionAdapter.new(
              reader_state_reader: c.resolve(:reader_state_reader),
              reader_session_mutator: c.resolve(:reader_session_mutator),
              ui_component_factory: c.resolve(:ui_component_factory),
              rendered_content_reader: c.resolve(:rendered_content_reader),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_annotation_editor_launcher(container)
          container.register_factory(:annotation_editor_launcher) do |c|
            Shoko::Adapters::Ui::Sessions::AnnotationEditorLauncherAdapter.new(
              annotation_overlay_ui_session: c.resolve(:annotation_overlay_ui_session)
            )
          end
        end

        def register_render_state_adapters(container)
          register_observer_render_adapters(container)
          register_view_model_builder_factory(container)
        end

        def register_observer_render_adapters(container)
          register_observer_registry(container)
          register_state_writers(container)
        end

        def register_observer_registry(container)
          container.register_factory(:observer_registry) do |c|
            Shoko::Adapters::Runtime::SessionState::ObserverRegistryAdapter.new(c.resolve(:global_state))
          end
        end

        def register_state_writers(container)
          container.register_factory(:render_state_writer) do |c|
            Shoko::Adapters::Runtime::SessionState::RenderStateWriterAdapter.new(
              c.resolve(:global_state),
              render_registry: c.resolve(:render_registry),
              logger: c.resolve(:logger)
            )
          end
          container.register_factory(:notification_writer) do |c|
            Shoko::Adapters::Runtime::SessionState::NotificationWriterAdapter.new(
              c.resolve(:global_state),
              text_sanitizer: c.resolve(:text_sanitizer)
            )
          end
        end

        def register_view_model_builder_factory(container)
          container.register_factory(:view_model_builder_factory) do |c|
            build_view_model_builder_factory(c)
          end
        end

        def build_view_model_builder_factory(container)
          reader_state_reader = container.resolve(:reader_state_reader)
          config_reader = container.resolve(:app_config_store)
          lambda do |doc|
            Shoko::Adapters::Ui::ViewModels::ReaderViewModelBuilder.new(
              reader_state_reader: reader_state_reader,
              config_reader: config_reader,
              doc: doc
            )
          end
        end
      end
    end
  end
end
