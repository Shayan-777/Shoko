# frozen_string_literal: true

require_relative '../../../../adapters/input/controllers/dependencies/reader_controller_dependencies'
require_relative '../../../../adapters/ui/dependency_sets'
require_relative 'controller_dependency_factory'
require_relative 'runtime_context_builder'
require_relative 'runtime_preparation'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderBuilder
          # Explicit reader dependency construction after runtime preparation.
          module DependencySet
            READER_UI_DIRECT_FIELDS = {
              observer_registry: :observer_registry,
              terminal_service: :terminal_service,
              reader_state_reader: :reader_state_reader,
              render_state_writer: :render_state_writer,
              rendered_content_reader: :rendered_content_reader,
              notification_service: :notification_service,
              logger: :logger,
              coordinate_service: :coordinate_service,
              view_model_builder_factory: :view_model_builder_factory,
              layout_service: :layout_service,
              layout_metrics: :layout_metrics,
              page_calculator: :page_calculator,
              wrapping_service: :wrapping_service,
              formatting_service: :formatting_service,
              kitty_image_renderer: :kitty_image_renderer,
              runtime_config: :runtime_config,
              reader_launch_state: :reader_launch_state,
              document: :document,
              annotation_service: :annotation_service,
            }.freeze

            ControllerDependencies = Data.define(
              :core,
              :state,
              :services,
              :runtime_boot,
              :runtime_startup,
              :mouse_support
            )

            Artifacts = Data.define(:reader_ui_dependencies, :controller_dependencies, :runtime_context)

            module_function

            def build(prepared)
              reader_ui_dependencies = build_reader_ui_dependencies(prepared)
              controller_dependencies = build_controller_dependencies(prepared)
              runtime_context = RuntimeContextBuilder.build(prepared, reader_ui_dependencies: reader_ui_dependencies)

              Artifacts.new(
                reader_ui_dependencies: reader_ui_dependencies,
                controller_dependencies: controller_dependencies,
                runtime_context: runtime_context
              )
            end

            def build_reader_ui_dependencies(prepared)
              Shoko::Adapters::Ui::ReaderUiDependencies.new(
                **extract_attributes(prepared, READER_UI_DIRECT_FIELDS),
                ui_state_reader: prepared.reader_runtime_context,
                sidebar_state_reader: prepared.reader_state_reader,
                config_reader: prepared.app_config_store
              )
            end
            private_class_method :build_reader_ui_dependencies

            def build_controller_dependencies(prepared)
              ControllerDependencyFactory.build(prepared)
            end
            private_class_method :build_controller_dependencies

            def extract_attributes(prepared, field_map)
              prepared_hash = prepared.to_h
              field_map.transform_values { |source| prepared_hash.fetch(source) }
            end
            private_class_method :extract_attributes
          end
        end
      end
    end
  end
end
