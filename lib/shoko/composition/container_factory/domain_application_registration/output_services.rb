# frozen_string_literal: true

require_relative '../../../adapters/ui/theme_context'

module Shoko
  module Bootstrap
    module ContainerFactory
      module DomainApplicationRegistration
        # Output and rendering service registration.
        module OutputServices
          def register_output_services(container)
            register_terminal_output_services(container)
            register_formatting_output_services(container)
            register_resource_output_services(container)
            register_runtime_output_services(container)
            register_ui_output_services(container)
          end

          private

          def register_terminal_output_services(container)
            register_clipboard_service(container)
            register_terminal_service(container)
            register_terminal_session(container)
            register_cli_progress_renderer(container)
          end

          def register_clipboard_service(container)
            container.register_factory(:clipboard_service) do |c|
              Shoko::Adapters::Output::Clipboard::ClipboardService.new(logger: c.resolve(:logger))
            end
          end

          def register_terminal_service(container)
            container.register_singleton(:terminal_service) do |c|
              Shoko::Adapters::Output::Terminal::TerminalService.new(
                runtime_config: c.resolve(:runtime_config),
                logger: c.resolve(:logger)
              )
            end
          end

          def register_terminal_session(container)
            container.register_singleton(:terminal_session) do |c|
              Shoko::Adapters::Output::Terminal::TerminalSessionAdapter.new(
                terminal_service: c.resolve(:terminal_service)
              )
            end
          end

          def register_cli_progress_renderer(container)
            container.register_factory(:cli_progress_renderer) do |c|
              Shoko::Adapters::Output::Terminal::CLIProgressRenderer.new(
                terminal_service: c.resolve(:terminal_service)
              )
            end
          end

          def register_formatting_output_services(container)
            register_wrapping_service(container)
            register_formatting_service(container)
          end

          def register_wrapping_service(container)
            container.register_singleton(:wrapping_service) do |c|
              Shoko::Adapters::Output::Formatting::WrappingService.new(
                text_metrics: c.resolve(:text_metrics),
                async_executor: c.resolve(:async_executor),
                reader_launch_state: c.resolve(:reader_launch_state),
                config_reader: c.resolve(:config_view),
                runtime_config: c.resolve(:runtime_config),
                formatting_service: c.resolve(:formatting_service),
                chapter_cache_factory: c.resolve(:chapter_cache_factory),
                logger: c.resolve(:logger)
              )
            end
          end

          def register_formatting_service(container)
            container.register_singleton(:formatting_service) do |c|
              xhtml_factory = c.resolve(:xhtml_parser_factory)
              logger = c.resolve(:logger)
              Shoko::Adapters::Output::Formatting::FormattingService.new(
                xhtml_parser_factory: xhtml_factory,
                format_parser_resolver: build_format_parser_resolver(xhtml_factory, logger),
                runtime_config: c.resolve(:runtime_config),
                logger: logger
              )
            end
          end

          def register_resource_output_services(container)
            register_epub_resource_loader(container)
            register_kitty_image_renderer(container)
          end

          def register_epub_resource_loader(container)
            container.register_singleton(:epub_resource_loader) do |c|
              Shoko::Adapters::BookSources::Epub::EpubResourceLoader.new(
                cache_root: c.resolve(:cache_paths).cache_root,
                file_writer: c.resolve(:atomic_file_writer),
                runtime_config: c.resolve(:runtime_config),
                logger: c.resolve(:logger)
              )
            end
          end

          def register_kitty_image_renderer(container)
            container.register_singleton(:kitty_image_renderer) do |c|
              loader = Shoko::Adapters::Output::Kitty::ResourceLoader.new(
                loader: c.resolve(:epub_resource_loader)
              )
              Shoko::Adapters::Output::Kitty::KittyImageRenderer.new(resource_loader: loader)
            end
          end

          def register_runtime_output_services(container)
            register_wrapped_lines_provider(container)
            register_file_writer(container)
            register_instrumentation_service(container)
            register_notification_service(container)
          end

          def register_wrapped_lines_provider(container)
            container.register_singleton(:wrapped_lines_provider) do |c|
              Shoko::Adapters::Runtime::SessionState::WrappedLinesProviderAdapter.new(
                formatting_service: c.resolve(:formatting_service),
                launch_state: c.resolve(:reader_launch_state)
              )
            end
          end

          def register_file_writer(container)
            container.register_singleton(:file_writer) do |c|
              Shoko::Adapters::Storage::FileWriterService.new(
                atomic_file_writer: c.resolve(:atomic_file_writer),
                logger: c.resolve(:logger)
              )
            end
          end

          def register_instrumentation_service(container)
            container.register_singleton(:instrumentation_service) do |c|
              Shoko::Adapters::Output::InstrumentationService.new(
                performance_monitor: c.resolve(:performance_monitor),
                perf_tracer: c.resolve(:perf_tracer),
                logger: c.resolve(:logger)
              )
            end
          end

          def register_notification_service(container)
            container.register_singleton(:notification_service) do |c|
              Shoko::Adapters::Output::NotificationService.new(
                logger: c.resolve(:logger),
                notification_writer: c.resolve(:notification_writer)
              )
            end
          end

          def register_ui_output_services(container)
            container.register_singleton(:ui_component_factory) do |c|
              build_ui_component_factory(c)
            end

            container.register_singleton(:render_registry) { |_c| Shoko::Adapters::Ui::RenderRegistry.new }

            container.register_factory(:dictionary_catalog_service) do |c|
              Shoko::Adapters::Storage::DictionaryCatalogService.new(logger: c.resolve(:logger))
            end
          end

          def build_ui_component_factory(container)
            config_reader = container.resolve(:config_view)
            fallback_mode = Shoko::Adapters::Output::Terminal::Terminal.color_mode
            theme_context = Shoko::Adapters::Ui::ThemeContext.apply!(
              theme_id: config_reader&.theme,
              fallback_color_mode: fallback_mode
            )
            Shoko::Adapters::Ui::ComponentFactory.new(
              config_reader: config_reader,
              fallback_color_mode: theme_context.color_mode
            )
          end
        end
      end
    end
  end
end
