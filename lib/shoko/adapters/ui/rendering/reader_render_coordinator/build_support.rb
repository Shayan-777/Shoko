# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Rendering
        # Component and dependency-building helpers for ReaderRenderCoordinator.
        module ReaderRenderCoordinatorBuildSupport
          private

          def build_frame_components
            vm_proc = -> { create_view_model }
            components.header = Shoko::Adapters::Ui::Components::HeaderComponent.new(vm_proc)
            components.content = build_content_component
            components.footer = Shoko::Adapters::Ui::Components::FooterComponent.new(vm_proc)
          end

          def build_content_component
            Shoko::Adapters::Ui::Components::ContentComponent.new(
              controller: deps.controller,
              render_dependencies: render_dependencies
            )
          end

          def build_sidebar_component
            Shoko::Adapters::Ui::Components::SidebarPanelComponent.new(
              deps.observer_registry,
              reader_ui_dependencies: deps.reader_dependencies
            )
          end

          def build_main_layout
            Shoko::Adapters::Ui::Components::Layouts::Vertical.new(
              [components.header, components.content, components.footer]
            )
          end

          def render_dependencies
            @render_dependencies ||= build_render_dependencies
          end

          def build_render_dependencies
            reader_deps = deps.reader_dependencies
            Shoko::Adapters::Ui::Components::Reading::RenderDependencies.new(
              **render_dependency_attributes(reader_deps)
            )
          end

          def render_dependency_attributes(reader_deps)
            base_render_dependency_attributes(reader_deps).merge(pipeline_render_dependency_attributes(reader_deps))
          end

          def base_render_dependency_attributes(reader_deps)
            {
              layout_service: reader_deps.layout_service,
              layout_metrics: reader_deps.layout_metrics,
              render_state_writer: reader_deps.render_state_writer,
              config_reader: reader_deps.config_reader,
              reader_state_reader: reader_deps.reader_state_reader,
              rendered_content_reader: reader_deps.rendered_content_reader,
              logger: reader_deps.logger,
              observer_registry: reader_deps.observer_registry,
            }
          end

          def pipeline_render_dependency_attributes(reader_deps)
            {
              reader_launch_state: reader_deps.reader_launch_state,
              document: reader_deps.document,
              page_calculator: reader_deps.page_calculator,
              formatting_service: reader_deps.formatting_service,
              wrapping_service: reader_deps.wrapping_service,
              kitty_image_renderer: reader_deps.kitty_image_renderer,
              runtime_config: reader_deps.runtime_config,
            }
          end
        end
      end
    end
  end
end
