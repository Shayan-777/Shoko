# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Composition::ContainerFactory::DomainApplicationRegistration do
  subject(:registration_host) do
    Class.new do
      include Shoko::Composition::ContainerFactory::DomainApplicationRegistration
    end.new
  end

  let(:container) { Shoko::Composition::DependencyContainer.new }

  it 'registers critical domain service bindings' do
    registration_host.register_domain_services(container)

    expected_keys = %i[
      navigation_service
      bookmark_service
      page_calculator
      coordinate_service
      reader_document_locator
      popup_position_service
      selection_service
      layout_service
      chapter_cache_factory
      core_annotation_service
      annotation_service
      dictionary_service
      dictionary_repository
      translation_service
    ]
    expected_keys.each do |key|
      expect(container.registered?(key)).to be(true), "expected domain service registration for #{key}"
    end
  end

  it 'registers critical application/output service bindings' do
    registration_host.register_application_services(container)

    expected_keys = %i[
      clipboard_service
      terminal_service
      terminal_session
      wrapping_service
      formatting_service
      epub_resource_loader
      kitty_image_renderer
      wrapped_lines_provider
      file_writer
      instrumentation_service
      notification_service
      ui_component_factory
      render_registry
      dictionary_catalog_service
      catalog_service
      download_service
      settings_service
      pagination_cache_preloader
      document_loader
    ]
    expected_keys.each do |key|
      expect(container.registered?(key)).to be(true), "expected application/output registration for #{key}"
    end
  end
end
