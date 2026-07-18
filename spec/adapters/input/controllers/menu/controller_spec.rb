# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::Controller do
  around do |example|
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  describe 'initialization' do
    let(:container) { Shoko::Composition::ContainerFactory.create_default_container }

    it 'creates successfully with dependency container' do
      menu = Shoko::Composition::ContainerFactory.build_menu_controller(container)
      expect(menu).to be_a(described_class)
    end

    it 'does not expose a container service-locator surface' do
      menu = Shoko::Composition::ContainerFactory.build_menu_controller(container)
      expect(menu).not_to respond_to(:container)
      # Observer wiring moved to the composition root; the controller no
      # longer carries the registry (or services it never used itself) just
      # so other builders can read them back off it.
      expect(menu).not_to respond_to(:observer_registry)
      expect(menu).not_to respond_to(:settings_service)
      expect(menu).not_to respond_to(:annotation_service)
    end

    it 'creates main_menu_component' do
      menu = Shoko::Composition::ContainerFactory.build_menu_controller(container)
      expect(menu.main_menu_component).to be_a(Shoko::Adapters::Ui::Components::MainMenuComponent)
    end

    it 'creates catalog service' do
      menu = Shoko::Composition::ContainerFactory.build_menu_controller(container)
      expect(menu.catalog).to be_a(Shoko::Application::UseCases::CatalogService)
    end

    it 'creates terminal service' do
      menu = Shoko::Composition::ContainerFactory.build_menu_controller(container)
      expect(menu.terminal_service).to be_a(Shoko::Adapters::Output::Terminal::TerminalService)
    end

    it 'creates frame_coordinator' do
      menu = Shoko::Composition::ContainerFactory.build_menu_controller(container)
      expect(menu.frame_coordinator).to be_a(Shoko::Adapters::Ui::Rendering::FrameCoordinator)
    end

    it 'creates render_pipeline' do
      menu = Shoko::Composition::ContainerFactory.build_menu_controller(container)
      expect(menu.render_pipeline).to be_a(Shoko::Adapters::Ui::Rendering::RenderPipeline)
    end

    it 'creates state_controller' do
      menu = Shoko::Composition::ContainerFactory.build_menu_controller(container)
      expect(menu.state_controller).to be_a(Shoko::Adapters::Input::Controllers::Menu::StateController)
    end

    it 'creates input_controller' do
      menu = Shoko::Composition::ContainerFactory.build_menu_controller(container)
      expect(menu.input_controller).to be_a(Shoko::Adapters::Input::Controllers::Menu::InputController)
    end

    it 'input_controller has dispatcher' do
      menu = Shoko::Composition::ContainerFactory.build_menu_controller(container)
      expect(menu.input_controller.dispatcher).to be_a(Shoko::Adapters::Input::Dispatcher)
    end

    it 'does not resolve inactive menu workflows and reader launch services during boot' do
      resolutions = Hash.new(0)
      lazy_services = %i[
        settings_service
        annotation_service
        download_service
        dictionary_catalog_service
        page_calculator
        document_loader
        pagination_cache_preloader
        reader_document_locator
      ]

      lazy_services.each do |service_name|
        container.register_factory(service_name) do
          resolutions[service_name] += 1
          double(service_name.to_s)
        end
      end

      Shoko::Composition::ContainerFactory.build_menu_controller(container)

      expect(resolutions).to eq({})
    end
  end

  describe 'screen components' do
    let(:container) { Shoko::Composition::ContainerFactory.create_default_container }
    let(:menu) { Shoko::Composition::ContainerFactory.build_menu_controller(container) }

    it 'provides browse screen via main_menu_component' do
      expect(menu.main_menu_component.browse_screen).to be_a(Shoko::Adapters::Ui::Components::Screens::BrowseScreenComponent)
    end

    it 'provides settings screen via main_menu_component' do
      expect(menu.main_menu_component.settings_screen).to be_a(Shoko::Adapters::Ui::Components::Screens::SettingsScreenComponent)
    end

    it 'provides download screen via main_menu_component' do
      expect(menu.main_menu_component.download_books_screen).to be_a(Shoko::Adapters::Ui::Components::Screens::DownloadBooksScreenComponent)
    end

    it 'provides annotations screen via main_menu_component' do
      expect(menu.main_menu_component.annotations_screen).to be_a(Shoko::Adapters::Ui::Components::Screens::AnnotationsScreenComponent)
    end

    it 'provides translator screen via main_menu_component' do
      expect(menu.main_menu_component.translator_screen).to be_a(Shoko::Adapters::Ui::Components::Screens::TranslatorScreenComponent)
    end

    it 'provides rss reader screen via main_menu_component' do
      expect(menu.main_menu_component.rss_reader_screen).to be_a(Shoko::Adapters::Ui::Components::Screens::RssReaderScreenComponent)
    end
  end

  describe 'key classification via DI' do
    let(:container) { Shoko::Composition::ContainerFactory.create_default_container }
    let(:menu) { Shoko::Composition::ContainerFactory.build_menu_controller(container) }

    it 'does not include adapter key definitions directly' do
      # Key classification is now handled via DI (:key_classifier port)
      expect(menu.class.included_modules).not_to include(Shoko::Shared::KeyDefinitions::Helpers)
    end
  end

  describe 'idle redraw cadence' do
    let(:container) { Shoko::Composition::ContainerFactory.create_default_container }
    let(:menu) { Shoko::Composition::ContainerFactory.build_menu_controller(container) }

    it 'polls on the blink interval while editing translator input so the caret animates' do
      allow(menu.menu_state_reader).to receive_messages(mode: :translator, translator_focus: :input)

      expect(menu.send(:input_poll_interval)).to eq(0.1)
    end
  end

  describe 'library metadata drawer' do
    let(:container) { Shoko::Composition::ContainerFactory.create_default_container }
    let(:menu) { Shoko::Composition::ContainerFactory.build_menu_controller(container) }
    let(:state) { container.resolve(:global_state) }

    it 'toggles metadata visibility in library mode' do
      menu.switch_to_mode(:library)
      expect(state.get(%i[menu library_details_open])).to eq(false)

      menu.library_toggle_details
      expect(state.get(%i[menu library_details_open])).to eq(true)

      menu.library_toggle_details
      expect(state.get(%i[menu library_details_open])).to eq(false)
    end
  end

  describe 'browse search selection' do
    let(:container) { Shoko::Composition::ContainerFactory.create_default_container }
    let(:menu) { Shoko::Composition::ContainerFactory.build_menu_controller(container) }
    let(:state) { container.resolve(:global_state) }

    it 'keeps browse results filtered when new catalog entries are assigned during active search' do
      full_list = [
        { 'path' => '/books/first.epub', 'name' => 'First' },
        { 'path' => '/books/target.epub', 'name' => 'Target' }
      ]

      state.update(
        %i[menu search_query] => 'target',
        %i[menu search_cursor] => 6,
        %i[menu mode] => :search,
        %i[menu search_active] => true
      )

      menu.main_menu_component.browse_screen.filtered_epubs = full_list

      browse_screen = menu.main_menu_component.browse_screen
      expect(browse_screen.filtered_count).to eq(1)
      expect(browse_screen.book_at(0)['path']).to eq('/books/target.epub')
    end

    it 'keeps browse-screen filtered selection authoritative for reader launch consumers' do
      full_list = [
        { 'path' => '/books/first.epub', 'name' => 'First' },
        { 'path' => '/books/target.epub', 'name' => 'Target' }
      ]
      filtered = [full_list[1]]

      menu.filtered_epubs = full_list
      menu.main_menu_component.browse_screen.filtered_epubs = filtered
      state.update([:menu, :browse_selected] => 0)

      expect(menu.main_menu_component.browse_screen.book_at(0)).to eq(filtered[0])
      expect(menu.main_menu_component.browse_screen.book_at(0)['path']).to eq('/books/target.epub')
    end

    it 'exits browse search mode when pressing escape' do
      menu.switch_to_search
      expect(menu.menu_state_reader.mode).to eq(:search)
      expect(state.get(%i[menu search_active])).to be(true)

      escape_key = Shoko::Shared::KeyDefinitions::ACTIONS[:cancel].first
      menu.input_controller.handle_keys([escape_key])

      expect(menu.menu_state_reader.mode).to eq(:browse)
      expect(state.get(%i[menu search_active])).to be(false)
    end
  end
end
