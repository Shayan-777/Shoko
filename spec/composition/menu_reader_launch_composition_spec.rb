# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Menu reader launch composition' do
  let(:menu_build_context_class) do
    Shoko::Composition::ContainerFactory::ControllerComposition::MenuBuilder::MenuBuildContext
  end
  SourceContext = Data.define(
    :menu_state_reader,
    :menu_session_mutator,
    :reader_state_reader,
    :app_config_store,
    :reader_session_store,
    :reader_view_state_store,
    :reader_pagination_store,
    :menu_session_store,
    :menu_transient_store,
    :reader_runtime_context,
    :catalog_service,
    :logger,
    :runtime_config,
    :file_probe,
    :path_ops,
    :clock,
    :translation_service,
    :reader_launch_state,
    :menu_launch_state,
    :download_service,
    :text_sanitizer,
    :dictionary_catalog_service,
    :dictionary_storage,
    :annotation_service,
    :cache_pointer_resolver,
    :reader_document_locator,
    :document_loader,
    :background_worker_builder,
    :recent_files_repository,
    :page_calculator,
    :pagination_cache_preloader,
    :pagination_cache,
    :instrumentation
  )

  let(:reader_view_state_store) { Object.new }
  let(:reader_pagination_store) { Object.new }
  let(:source_context) do
    SourceContext.new(
      menu_state_reader: Object.new,
      menu_session_mutator: Object.new,
      reader_state_reader: Object.new,
      app_config_store: Object.new,
      reader_session_store: Object.new,
      reader_view_state_store: reader_view_state_store,
      reader_pagination_store: reader_pagination_store,
      menu_session_store: Object.new,
      menu_transient_store: Object.new,
      reader_runtime_context: Object.new,
      catalog_service: Object.new,
      logger: Object.new,
      runtime_config: Object.new,
      file_probe: Object.new,
      path_ops: Object.new,
      clock: Object.new,
      translation_service: Object.new,
      reader_launch_state: Object.new,
      menu_launch_state: Object.new,
      download_service: Object.new,
      text_sanitizer: Object.new,
      dictionary_catalog_service: Object.new,
      dictionary_storage: Object.new,
      annotation_service: Object.new,
      cache_pointer_resolver: Object.new,
      reader_document_locator: Object.new,
      document_loader: Object.new,
      background_worker_builder: Object.new,
      recent_files_repository: Object.new,
      page_calculator: Object.new,
      pagination_cache_preloader: Object.new,
      pagination_cache: Object.new,
      instrumentation: Object.new
    )
  end
  let(:reader_launch_ports) { Object.new }
  let(:composition_builder) do
    Class.new do
      include Shoko::Composition::ContainerFactory::ControllerComposition::MenuBuilder::CompositionSupport

      def build(context)
        build_composition_context(context)
      end

      private

      def build_pagination_orchestrator(_context)
        Object.new
      end
    end.new
  end

  it 'resolves split reader stores into the menu build context' do
    eager_resolutions =
      Shoko::Composition::ContainerFactory::ControllerComposition::MenuBuilder::EAGER_SERVICE_MAP.values.to_h do |service|
        [service, Object.new]
      end
    reader_launch_state = instance_double('ReaderLaunchState', preloaded_document: Object.new)
    reader_session_store = Object.new
    container = double('Container')

    allow(container).to receive(:resolve) do |key|
      {
        **eager_resolutions,
        reader_launch_state: reader_launch_state,
        reader_session_store: reader_session_store,
        reader_view_state_store: reader_view_state_store,
        reader_pagination_store: reader_pagination_store,
      }.fetch(key)
    end

    context = menu_build_context_class.resolve(container)

    expect(context.reader_session_store).to equal(reader_session_store)
    expect(context.reader_view_state_store).to equal(reader_view_state_store)
    expect(context.reader_pagination_store).to equal(reader_pagination_store)
  end

  it 'carries split reader stores into the reader launch progress orchestration' do
    composition_context = composition_builder.build(source_context)

    expect(composition_context.reader_view_state_store).to equal(reader_view_state_store)
    expect(composition_context.reader_pagination_store).to equal(reader_pagination_store)

    described_factory = Shoko::Composition::ContainerFactory::ControllerComposition::MenuStateControllerComposer::ReaderLaunchServiceFactory
    described_factory.send(:require_reader_launch_dependencies)

    expect do
      described_factory.send(
        :build_progress_orchestration,
        context: composition_context,
        reader_launch_ports: reader_launch_ports
      )
    end.not_to raise_error
  end
end
