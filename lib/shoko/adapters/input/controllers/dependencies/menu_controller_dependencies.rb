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
              :command_bus
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
              define_method(field) { core.public_send(field) }
            end

            SERVICE_FIELDS.each do |field|
              define_method(field) { services.public_send(field) }
            end

            PLATFORM_FIELDS.each do |field|
              define_method(field) { platform.public_send(field) }
            end

            def validate!
              missing = REQUIRED_FIELDS.select { |field| public_send(field).nil? }
              unless missing.empty?
                raise ArgumentError, "Missing required menu dependencies: #{missing.join(', ')}"
              end

              unless state_controller_factory.respond_to?(:call)
                raise ArgumentError, 'state_controller_factory is required and must respond to :call'
              end

              self
            end
          end
        end
      end
    end
  end
end
