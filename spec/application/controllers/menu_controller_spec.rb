# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Controllers::MenuController do
  around do |example|
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  describe 'initialization' do
    let(:container) { Shoko::Application::ContainerFactory.create_default_container }

    it 'creates successfully with dependency container' do
      menu = Shoko::Application::ContainerFactory.build_menu_controller(container)
      expect(menu).to be_a(described_class)
    end

    it 'exposes state' do
      menu = Shoko::Application::ContainerFactory.build_menu_controller(container)
      expect(menu.state).to be_a(Shoko::Adapters::State::ObserverStateStore)
    end

    it 'does not expose a container service-locator surface' do
      menu = Shoko::Application::ContainerFactory.build_menu_controller(container)
      expect(menu).not_to respond_to(:container)
    end

    it 'creates main_menu_component' do
      menu = Shoko::Application::ContainerFactory.build_menu_controller(container)
      expect(menu.main_menu_component).to be_a(Shoko::Adapters::Output::Ui::Components::MainMenuComponent)
    end

    it 'creates catalog service' do
      menu = Shoko::Application::ContainerFactory.build_menu_controller(container)
      expect(menu.catalog).to be_a(Shoko::Application::UseCases::CatalogService)
    end

    it 'creates terminal service' do
      menu = Shoko::Application::ContainerFactory.build_menu_controller(container)
      expect(menu.terminal_service).to be_a(Shoko::Adapters::Output::Terminal::TerminalService)
    end

    it 'creates frame_coordinator' do
      menu = Shoko::Application::ContainerFactory.build_menu_controller(container)
      expect(menu.frame_coordinator).to be_a(Shoko::Adapters::Output::Ui::Rendering::FrameCoordinator)
    end

    it 'creates render_pipeline' do
      menu = Shoko::Application::ContainerFactory.build_menu_controller(container)
      expect(menu.render_pipeline).to be_a(Shoko::Adapters::Output::Ui::Rendering::RenderPipeline)
    end

    it 'creates state_controller' do
      menu = Shoko::Application::ContainerFactory.build_menu_controller(container)
      expect(menu.state_controller).to be_a(Shoko::Application::Controllers::Menu::StateController)
    end

    it 'creates input_controller' do
      menu = Shoko::Application::ContainerFactory.build_menu_controller(container)
      expect(menu.input_controller).to be_a(Shoko::Application::Controllers::Menu::InputController)
    end

    it 'input_controller has dispatcher' do
      menu = Shoko::Application::ContainerFactory.build_menu_controller(container)
      expect(menu.input_controller.dispatcher).to be_a(Shoko::Adapters::Input::Dispatcher)
    end
  end

  describe 'screen components' do
    let(:container) { Shoko::Application::ContainerFactory.create_default_container }
    let(:menu) { Shoko::Application::ContainerFactory.build_menu_controller(container) }

    it 'provides browse screen via main_menu_component' do
      expect(menu.main_menu_component.browse_screen).to be_a(Shoko::Adapters::Output::Ui::Components::Screens::BrowseScreenComponent)
    end

    it 'provides settings screen via main_menu_component' do
      expect(menu.main_menu_component.settings_screen).to be_a(Shoko::Adapters::Output::Ui::Components::Screens::SettingsScreenComponent)
    end

    it 'provides download screen via main_menu_component' do
      expect(menu.main_menu_component.download_books_screen).to be_a(Shoko::Adapters::Output::Ui::Components::Screens::DownloadBooksScreenComponent)
    end

    it 'provides annotations screen via main_menu_component' do
      expect(menu.main_menu_component.annotations_screen).to be_a(Shoko::Adapters::Output::Ui::Components::Screens::AnnotationsScreenComponent)
    end
  end

  describe 'key classification via DI' do
    let(:container) { Shoko::Application::ContainerFactory.create_default_container }
    let(:menu) { Shoko::Application::ContainerFactory.build_menu_controller(container) }

    it 'does not include adapter key definitions directly' do
      # Key classification is now handled via DI (:key_classifier port)
      expect(menu.class.included_modules).not_to include(Shoko::Adapters::Input::KeyDefinitions::Helpers)
    end
  end

  describe 'library path resolution' do
    let(:container) { Shoko::Application::ContainerFactory.create_default_container }
    let(:menu) { Shoko::Application::ContainerFactory.build_menu_controller(container) }

    it 'prefers cache pointer open_path over epub_path when both are available' do
      Dir.mktmpdir('menu-library-path') do |dir|
        source = File.join(dir, 'book.epub')
        pointer = File.join(dir, 'book.cache')
        File.write(source, 'source')
        File.write(pointer, 'pointer')

        item = Struct.new(:open_path, :epub_path).new(pointer, source)
        allow(menu.state_controller).to receive(:valid_cache_path?).with(pointer).and_return(true)

        chosen = menu.send(:resolve_library_path, item)
        expect(chosen).to eq(pointer)
      end
    end

    it 'falls back to epub_path when cache pointer is unavailable' do
      Dir.mktmpdir('menu-library-path-fallback') do |dir|
        source = File.join(dir, 'book.epub')
        pointer = File.join(dir, 'missing.cache')
        File.write(source, 'source')

        item = Struct.new(:open_path, :epub_path).new(pointer, source)
        allow(menu.state_controller).to receive(:valid_cache_path?).with(pointer).and_return(false)

        chosen = menu.send(:resolve_library_path, item)
        expect(chosen).to eq(source)
      end
    end
  end

  describe 'browse search selection' do
    let(:container) { Shoko::Application::ContainerFactory.create_default_container }
    let(:menu) { Shoko::Application::ContainerFactory.build_menu_controller(container) }

    it 'keeps browse results filtered when new catalog entries are assigned during active search' do
      full_list = [
        { 'path' => '/books/first.epub', 'name' => 'First' },
        { 'path' => '/books/target.epub', 'name' => 'Target' }
      ]

      menu.state.update(
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

    it 'opens selected book from browse-screen filtered list instead of stale controller list' do
      full_list = [
        { 'path' => '/books/first.epub', 'name' => 'First' },
        { 'path' => '/books/target.epub', 'name' => 'Target' }
      ]
      filtered = [full_list[1]]

      menu.filtered_epubs = full_list
      menu.main_menu_component.browse_screen.filtered_epubs = filtered
      menu.state.update([:menu, :browse_selected] => 0)

      selected = menu.send(:selected_browse_book)
      expect(selected).to eq(filtered[0])
      expect(selected['path']).to eq('/books/target.epub')
    end

    it 'exits browse search mode when pressing escape' do
      menu.switch_to_search
      expect(menu.menu_state_reader.mode).to eq(:search)
      expect(menu.state.get(%i[menu search_active])).to be(true)

      escape_key = Shoko::Adapters::Input::KeyDefinitions::ACTIONS[:cancel].first
      menu.input_controller.handle_keys([escape_key])

      expect(menu.menu_state_reader.mode).to eq(:browse)
      expect(menu.state.get(%i[menu search_active])).to be(false)
    end
  end
end
