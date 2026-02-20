# frozen_string_literal: true

require_relative '../components/header_component'
require_relative '../components/content_component'
require_relative '../components/footer_component'
require_relative '../components/sidebar_panel_component'
require_relative '../components/dictionary_panel_component'
require_relative '../components/layouts/vertical'
require_relative '../components/layouts/horizontal'
require_relative '../components/layouts/horizontal_three'
require_relative '../components/tooltip_overlay_component'

module Shoko
  module Adapters::Output::Ui
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
          :reader_state_reader,
          keyword_init: true
        )

        RenderComponents = Struct.new(
          :header,
          :content,
          :footer,
          :sidebar,
          :main_layout,
          :root_layout,
          :overlay,
          keyword_init: true
        )

        def initialize(dependencies:)
          @deps = dependencies
          @components = RenderComponents.new
          @render_state_writer = deps.render_state_writer
        end

        def build_component_layout
          vm_proc = -> { create_view_model }
          components.header = Shoko::Adapters::Output::Ui::Components::HeaderComponent.new(vm_proc)
          components.content = Shoko::Adapters::Output::Ui::Components::ContentComponent.new(
            controller: deps.controller,
            render_dependencies: render_dependencies
          )
          components.footer = Shoko::Adapters::Output::Ui::Components::FooterComponent.new(vm_proc)
          components.sidebar = Shoko::Adapters::Output::Ui::Components::SidebarPanelComponent.new(
            deps.observer_registry,
            reader_ui_dependencies: deps.reader_dependencies
          )
          components.main_layout = Shoko::Adapters::Output::Ui::Components::Layouts::Vertical.new([
                                                                                                    components.header,
                                                                                                    components.content,
                                                                                                    components.footer,
                                                                                                  ])

          rebuild_root_layout
          build_overlay
        end

        def rebuild_root_layout
          sidebar_visible = reader_state_reader&.sidebar_visible?
          dictionary_panel = reader_state_reader&.dictionary_panel
          dictionary_visible = dictionary_panel.respond_to?(:visible?) && dictionary_panel.visible?

          if sidebar_visible || dictionary_visible
            left = sidebar_visible ? components.sidebar : nil
            right = dictionary_visible ? dictionary_panel : nil
            components.root_layout = Shoko::Adapters::Output::Ui::Components::Layouts::HorizontalThree.new(
              left,
              components.main_layout,
              right
            )
          else
            components.root_layout = components.main_layout
          end
        end

        def draw_screen
          height, width = deps.terminal_service.size
          tick_notifications
          handle_resize(width, height) if size_changed?(width, height)

          # Ensure components are built before rendering
          unless components.root_layout && components.overlay
            log_debug('draw_screen.components_not_ready',
                      has_root_layout: !components.root_layout.nil?,
                      has_overlay: !components.overlay.nil?)
            return
          end

          deps.frame_coordinator.with_frame do |surface, root_bounds, _w, _h|
            mode = reader_state_reader&.mode
            mode_component = deps.ui_controller.current_mode
            if mode == :annotation_editor && mode_component
              deps.render_pipeline.render_mode_component(mode_component, surface, root_bounds)
            else
              # Clear rendered lines before rendering so overlays get fresh geometry data
              clear_rendered_lines_for_frame
              deps.render_pipeline.render_layout(surface, root_bounds, components.root_layout, components.overlay)
            end
          end
        rescue StandardError => e
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
          theme = config_reader&.theme || :default
          palette = Shoko::Adapters::Output::Ui::Constants::Themes.palette_for(theme)
          Shoko::Adapters::Output::Ui::Components::RenderStyle.configure(palette)
        rescue StandardError
          Shoko::Adapters::Output::Ui::Components::RenderStyle.configure(Shoko::Adapters::Output::Ui::Constants::Themes::DEFAULT_PALETTE)
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
          rescue StandardError
            nil
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
          deps.pagination.refresh_after_resize(width: width, height: height)
          clear_wrapping_cache
          refresh_dictionary_display_mode(width, height)
        end

        def clear_wrapping_cache
          prior_width = reader_state_reader&.last_width
          return unless prior_width&.positive?

          deps.wrapping_service&.clear_cache_for_width(prior_width)
        rescue StandardError
          # best-effort cache clear
        end

        def build_overlay
          components.overlay = Shoko::Adapters::Output::Ui::Components::TooltipOverlayComponent.new(
            coordinate_service: deps.coordinate_service,
            reader_state_reader: reader_state_reader,
            rendered_content_reader: render_dependencies.rendered_content_reader
          )
        end

        def refresh_dictionary_display_mode(width, height)
          ui = deps.ui_controller
          return unless ui.respond_to?(:refresh_dictionary_display_mode)

          ui.refresh_dictionary_display_mode(terminal_width: width, terminal_height: height)
        rescue StandardError
          nil
        end

        def tick_notifications
          notification_service&.tick
        end

        def notification_service
          deps.notification_service
        end

        def log_debug(event, **data)
          deps.logger&.debug(event, **data)
        rescue StandardError
          # Silently ignore logging failures
        end

        def clear_rendered_lines_for_frame
          @render_state_writer&.clear_rendered_lines
        rescue StandardError => e
          log_debug('draw_screen.clear_rendered_lines_failed',
                    error: e.class.name,
                    message: e.message)
        end

        def config_reader
          deps.config_reader
        end

        def reader_state_reader
          deps.reader_state_reader
        end

        def render_dependencies
          @render_dependencies ||= begin
            reader_deps = deps.reader_dependencies
            Shoko::Adapters::Output::Ui::Components::Reading::RenderDependencies.new(
              layout_service: reader_deps.layout_service,
              layout_metrics: reader_deps.layout_metrics,
              render_state_writer: reader_deps.render_state_writer,
              config_reader: reader_deps.config_reader,
              reader_state_reader: reader_deps.reader_state_reader,
              rendered_content_reader: reader_deps.rendered_content_reader,
              logger: reader_deps.logger,
              observer_registry: reader_deps.observer_registry,
              reader_session_context: reader_deps.reader_session_context,
              document: reader_deps.document,
              page_calculator: reader_deps.page_calculator,
              formatting_service: reader_deps.formatting_service,
              wrapping_service: reader_deps.wrapping_service,
              kitty_image_renderer: reader_deps.kitty_image_renderer,
              runtime_config: reader_deps.runtime_config
            )
          end
        end
      end
    end
  end
end
