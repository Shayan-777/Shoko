# frozen_string_literal: true

require_relative '../components/header_component'
require_relative '../components/content_component'
require_relative '../components/status_bar_component'
require_relative '../components/status_bar/reader_status_context_builder'
require_relative '../components/sidebar_panel_component'
require_relative '../components/layouts/vertical'
require_relative '../components/layouts/horizontal_three'
require_relative '../components/tooltip_overlay_component'
require_relative '../theme_context'

module Shoko
  module Adapters
    module Ui
      module Rendering
        # Coordinates render/layout setup and per-frame drawing for the reader.
        class ReaderRenderCoordinator
          Dependencies = Struct.new(
            :controller,
            :observer_registry,
            :ui_state_reader,
            :terminal_service,
            :frame_coordinator,
            :render_pipeline,
            :ui_controller,
            :wrapping_service,
            :pagination,
            :doc,
            :reader_dependencies,
            :coordinate_service,
            :notification_service,
            :logger,
            :render_state_writer,
            :config_reader,
            :view_model_builder_factory,
            :reader_state_reader
          )

          RenderComponents = Struct.new(:header, :content, :status_bar, :sidebar, :main_layout, :root_layout, :overlay)

          def initialize(dependencies:)
            @deps = dependencies
            @components = RenderComponents.new
            @render_state_writer = deps.render_state_writer
          end

          def build_component_layout
            build_frame_components
            components.sidebar = build_sidebar_component
            components.main_layout = build_main_layout
            rebuild_root_layout
            build_overlay
          end

          def rebuild_root_layout
            # The dictionary now renders as a bar-anchored overlay card, so only
            # the sidebar splits the reader layout.
            if reader_state_reader&.sidebar_visible?
              components.root_layout = Shoko::Adapters::Ui::Components::Layouts::HorizontalThree.new(
                components.sidebar,
                components.main_layout,
                nil
              )
            else
              components.root_layout = components.main_layout
            end
          end

          def draw_screen
            height, width = deps.terminal_service.size
            tick_notifications
            handle_resize(width, height) if size_changed?(width, height)
            return unless render_components_ready?

            deps.frame_coordinator.with_frame do |surface, root_bounds, _w, _h|
              render_frame(surface, root_bounds)
            end
          rescue Shoko::Error => e
            log_debug('draw_screen.error', error: e.class.name, message: e.message)
          end

          def refresh_highlighting
            draw_screen
          end

          def force_redraw
            components.content&.invalidate
          end

          def render_loading_overlay
            deps.frame_coordinator.render_loading_overlay
          end

          def apply_theme_palette
            Shoko::Adapters::Ui::ThemeContext.apply!(theme_id: config_reader&.theme)
          rescue Shoko::Error
            Shoko::Adapters::Ui::ThemeContext.apply!(theme_id: :default)
          end

          def sidebar_component
            components.sidebar
          end

          def sidebar_bounds(total_width, total_height)
            sidebar = components.sidebar
            return nil unless sidebar

            sidebar.sidebar_bounds_for(total_width, total_height)
          end

          # Remove observer registrations for all UI components created during this session.
          def cleanup_observers
            registry = deps.observer_registry
            return unless registry

            [components.sidebar, components.content, components.overlay].compact.each do |component|
              registry.remove_observer(component)
            end
          end

          private

          attr_reader :deps, :components

          def create_view_model
            builder = deps.view_model_builder_factory&.call(deps.doc)
            return nil unless builder

            builder.build(deps.pagination.page_info)
          end

          def size_changed?(width, height)
            deps.ui_state_reader.terminal_size_changed?(width, height)
          end

          def handle_resize(width, height)
            # Repagination now runs on the worker thread; only drop the old
            # width's wrapped-line cache when a fresh rebuild actually started, so
            # the clear happens once per resize rather than every poll frame while
            # the (now animated) spinner is up.
            started = deps.pagination.refresh_after_resize(width: width, height: height)
            clear_wrapping_cache if started
          end

          def render_components_ready?
            return true if components.root_layout && components.overlay

            log_debug(
              'draw_screen.components_not_ready',
              has_root_layout: !components.root_layout.nil?,
              has_overlay: !components.overlay.nil?
            )
            false
          end

          def render_frame(surface, root_bounds)
            mode_component = annotation_editor_mode_component
            return deps.render_pipeline.render_mode_component(mode_component, surface, root_bounds) if mode_component

            clear_rendered_lines_for_frame
            deps.render_pipeline.render_layout(surface, root_bounds, components.root_layout, components.overlay)
          end

          def annotation_editor_mode_component
            mode_component = deps.ui_controller.current_mode
            return nil unless reader_state_reader&.mode == :annotation_editor
            return nil unless mode_component

            mode_component
          end

          def clear_wrapping_cache
            prior_width = reader_state_reader&.last_width
            return unless prior_width&.positive?

            deps.wrapping_service&.clear_cache_for_width(prior_width)
          rescue Shoko::Error
            # best-effort cache clear
          end

          def build_overlay
            components.overlay = Shoko::Adapters::Ui::Components::TooltipOverlayComponent.new(
              coordinate_service: deps.coordinate_service,
              reader_state_reader: reader_state_reader,
              rendered_content_reader: render_dependencies.rendered_content_reader
            )
          end

          def tick_notifications
            notification_service&.tick
          end

          def notification_service
            deps.notification_service
          end

          def log_debug(event, **data)
            deps.logger&.debug(event, **data)
          rescue Shoko::Error
            # Silently ignore logging failures
          end

          def clear_rendered_lines_for_frame
            @render_state_writer&.clear_rendered_lines
          rescue Shoko::Error => e
            log_debug('draw_screen.clear_rendered_lines_failed', error: e.class.name, message: e.message)
          end

          def config_reader
            deps.config_reader
          end

          def reader_state_reader
            deps.reader_state_reader
          end

          # Component and dependency-building helpers for ReaderRenderCoordinator.
          def build_frame_components
            vm_proc = -> { create_view_model }
            components.header = Shoko::Adapters::Ui::Components::HeaderComponent.new(vm_proc)
            components.content = build_content_component
            components.status_bar = Shoko::Adapters::Ui::Components::StatusBarComponent.new(
              Shoko::Adapters::Ui::Components::StatusBar::ReaderStatusContextBuilder.new(
                vm_proc, reader_state_reader: reader_state_reader, recalc_status_reader: deps.pagination
              )
            )
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
              [components.header, components.content, components.status_bar]
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
