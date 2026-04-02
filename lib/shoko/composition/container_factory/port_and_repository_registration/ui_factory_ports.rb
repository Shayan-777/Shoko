# frozen_string_literal: true

require_relative '../../../adapters/input/input_system_factory_adapter'
require_relative '../../../adapters/ui/rendering_factory'
require_relative '../../../adapters/storage/book_cache_pipeline_factory_adapter'

module Shoko
  module Composition
    module ContainerFactory
      # Registers UI and rendering factory ports for composition wiring.
      module PortAndRepositoryRegistrationUiFactoryPorts
        private

        def register_ui_factory_ports(container)
          container.register_singleton(:input_system_factory) do |_c|
            Shoko::Adapters::Input::InputSystemFactoryAdapter.new
          end
          container.register_singleton(:rendering_factory) do |_c|
            Shoko::Adapters::Ui::RenderingFactory.new
          end
          container.register_singleton(:book_cache_pipeline_factory) do |c|
            Shoko::Adapters::Storage::BookCachePipelineFactoryAdapter.new(
              image_cache_warmup: c.resolve(:image_cache_warmup)
            )
          end
        end
      end
    end
  end
end
