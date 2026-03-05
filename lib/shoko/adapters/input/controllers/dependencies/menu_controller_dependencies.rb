# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dependencies
          # Groups MenuController collaborators into bounded bundles.
          MenuControllerDependencies = Data.define(:core, :services, :platform) do
            MenuCoreBundle = Data.define(
              :observer_registry,
              :catalog,
              :terminal_service,
              :frame_coordinator,
              :render_pipeline,
              :menu_ui_dependencies,
              :ui_component_factory,
              :key_classifier,
              :input_system_factory,
              :menu_state_reader,
              :menu_state_writer,
              :command_bus,
              :intent_handler_factory
            )

            MenuServiceBundle = Data.define(
              :state_controller_factory,
              :notification_service,
              :settings_service,
              :annotation_service,
              :logger
            )

            MenuPlatformBundle = Data.define(
              :file_probe,
              :path_ops,
              :clock,
              :process_control
            )

            CORE_FIELDS = %i[
              observer_registry
              catalog
              terminal_service
              frame_coordinator
              render_pipeline
              menu_ui_dependencies
              ui_component_factory
              key_classifier
              input_system_factory
              menu_state_reader
              menu_state_writer
              command_bus
              intent_handler_factory
            ].freeze

            SERVICE_FIELDS = %i[
              state_controller_factory
              notification_service
              settings_service
              annotation_service
              logger
            ].freeze

            PLATFORM_FIELDS = %i[
              file_probe
              path_ops
              clock
              process_control
            ].freeze

            REQUIRED_FIELDS = %i[
              observer_registry
              catalog
              terminal_service
              frame_coordinator
              render_pipeline
              menu_ui_dependencies
              ui_component_factory
              key_classifier
              input_system_factory
              menu_state_reader
              menu_state_writer
              command_bus
              intent_handler_factory
              state_controller_factory
              clock
            ].freeze

            class << self
              def build(**kwargs)
                new(
                  core: MenuCoreBundle.new(**slice(kwargs, CORE_FIELDS)),
                  services: MenuServiceBundle.new(**slice(kwargs, SERVICE_FIELDS)),
                  platform: MenuPlatformBundle.new(**slice(kwargs, PLATFORM_FIELDS))
                )
              end

              private

              def slice(values, keys)
                keys.to_h { |key| [key, values[key]] }
              end
            end

            CORE_FIELDS.each do |field|
              define_method(field) { core.to_h[field] }
            end

            SERVICE_FIELDS.each do |field|
              define_method(field) { services.to_h[field] }
            end

            PLATFORM_FIELDS.each do |field|
              define_method(field) { platform.to_h[field] }
            end

            def validate!
              values = core.to_h.merge(services.to_h).merge(platform.to_h)
              missing = REQUIRED_FIELDS.select { |field| values[field].nil? }
              raise ArgumentError, "Missing required menu dependencies: #{missing.join(', ')}" unless missing.empty?

              raise ArgumentError, 'state_controller_factory is required' if state_controller_factory.nil?

              self
            end
          end
        end
      end
    end
  end
end
