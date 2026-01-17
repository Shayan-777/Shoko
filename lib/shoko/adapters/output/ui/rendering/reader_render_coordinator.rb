# frozen_string_literal: true

require_relative '../components/header_component'
require_relative '../components/content_component'
require_relative '../components/footer_component'
require_relative '../components/sidebar_panel_component'
require_relative '../components/layouts/vertical'
require_relative '../components/layouts/horizontal'
require_relative '../components/tooltip_overlay_component'
require_relative '../../../../application/ui/reader_view_model_builder'

module Shoko
  module Adapters::Output::Ui
    module Rendering
      # Coordinates render/layout setup and per-frame drawing for the reader.
      class ReaderRenderCoordinator
        Dependencies = Struct.new(
          :controller,
          :state,
          :dependencies,
          :terminal_service,
          :frame_coordinator,
          :render_pipeline,
          :ui_controller,
          :wrapping_service,
          :pagination,
          :doc,
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
        end

        def build_component_layout
          vm_proc = -> { create_view_model }
          components.header = Shoko::Adapters::Output::Ui::Components::HeaderComponent.new(vm_proc)
          components.content = Shoko::Adapters::Output::Ui::Components::ContentComponent.new(deps.controller)
          components.footer = Shoko::Adapters::Output::Ui::Components::FooterComponent.new(vm_proc)
          components.sidebar = Shoko::Adapters::Output::Ui::Components::SidebarPanelComponent.new(deps.state,
                                                                                                  deps.dependencies)
          components.main_layout = Shoko::Adapters::Output::Ui::Components::Layouts::Vertical.new([
                                                                                                    components.header,
                                                                                                    components.content,
                                                                                                    components.footer,
                                                                                                  ])

          rebuild_root_layout
          build_overlay
        end

        def rebuild_root_layout
          components.root_layout = if deps.state.get(%i[reader sidebar_visible])
                                     Shoko::Adapters::Output::Ui::Components::Layouts::Horizontal.new(
                                       components.sidebar, components.main_layout
                                     )
                                   else
                                     components.main_layout
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
            mode = deps.state.get(%i[reader mode])
            mode_component = deps.ui_controller.current_mode
            if mode == :annotation_editor && mode_component
              deps.render_pipeline.render_mode_component(mode_component, surface, root_bounds)
            else
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
          theme = Shoko::Application::Selectors::ConfigSelectors.theme(deps.state) || :default
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

        private

        attr_reader :deps, :components

        def create_view_model
          builder = Shoko::Application::UI::ReaderViewModelBuilder.new(deps.state, deps.doc)
          builder.build(deps.pagination.page_info)
        end

        def size_changed?(width, height)
          deps.state.terminal_size_changed?(width, height)
        end

        def handle_resize(width, height)
          deps.pagination.refresh_after_resize(width: width, height: height)
          clear_wrapping_cache
        end

        def clear_wrapping_cache
          prior_width = deps.state.get(%i[reader last_width])
          return unless prior_width&.positive?

          deps.wrapping_service&.clear_cache_for_width(prior_width)
        rescue StandardError
          # best-effort cache clear
        end

        def build_overlay
          coord = deps.dependencies.resolve(:coordinate_service)
          components.overlay = Shoko::Adapters::Output::Ui::Components::TooltipOverlayComponent.new(
            deps.controller,
            coordinate_service: coord
          )
        end

        def tick_notifications
          notification_service&.tick(deps.state)
        end

        def notification_service
          return @notification_service if defined?(@notification_service)

          @notification_service = begin
            deps.dependencies.resolve(:notification_service)
          rescue StandardError
            nil
          end
        end

        def log_debug(event, **data)
          logger = begin
            deps.dependencies.resolve(:logger)
          rescue StandardError
            nil
          end
          logger&.debug(event, **data)
        rescue StandardError
          # Silently ignore logging failures
        end
      end
    end
  end
end
