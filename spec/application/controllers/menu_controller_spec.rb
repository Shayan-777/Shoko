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
      menu = described_class.new(container)
      expect(menu).to be_a(described_class)
    end

    it 'exposes state' do
      menu = described_class.new(container)
      expect(menu.state).to be_a(Shoko::Application::Infrastructure::ObserverStateStore)
    end

    it 'exposes dependencies' do
      menu = described_class.new(container)
      expect(menu.dependencies).to be(container)
    end

    it 'creates main_menu_component' do
      menu = described_class.new(container)
      expect(menu.main_menu_component).to be_a(Shoko::Adapters::Output::Ui::Components::MainMenuComponent)
    end

    it 'creates catalog service' do
      menu = described_class.new(container)
      expect(menu.catalog).to be_a(Shoko::Application::UseCases::CatalogService)
    end

    it 'creates terminal service' do
      menu = described_class.new(container)
      expect(menu.terminal_service).to be_a(Shoko::Adapters::Output::Terminal::TerminalService)
    end

    it 'creates frame_coordinator' do
      menu = described_class.new(container)
      expect(menu.frame_coordinator).to be_a(Shoko::Adapters::Output::Ui::Rendering::FrameCoordinator)
    end

    it 'creates render_pipeline' do
      menu = described_class.new(container)
      expect(menu.render_pipeline).to be_a(Shoko::Adapters::Output::Ui::Rendering::RenderPipeline)
    end

    it 'creates state_controller' do
      menu = described_class.new(container)
      expect(menu.state_controller).to be_a(Shoko::Application::Controllers::Menu::StateController)
    end

    it 'creates input_controller' do
      menu = described_class.new(container)
      expect(menu.input_controller).to be_a(Shoko::Application::Controllers::Menu::InputController)
    end

    it 'input_controller has dispatcher' do
      menu = described_class.new(container)
      expect(menu.input_controller.dispatcher).to be_a(Shoko::Adapters::Input::Dispatcher)
    end
  end

  describe 'screen accessors' do
    let(:container) { Shoko::Application::ContainerFactory.create_default_container }
    let(:menu) { described_class.new(container) }

    it 'provides browse_screen' do
      expect(menu.browse_screen).to be_a(Shoko::Adapters::Output::Ui::Components::Screens::BrowseScreenComponent)
    end

    it 'provides settings_screen' do
      expect(menu.settings_screen).to be_a(Shoko::Adapters::Output::Ui::Components::Screens::SettingsScreenComponent)
    end

    it 'provides download_books_screen' do
      expect(menu.download_books_screen).to be_a(Shoko::Adapters::Output::Ui::Components::Screens::DownloadBooksScreenComponent)
    end

    it 'provides annotations_screen' do
      expect(menu.annotations_screen).to be_a(Shoko::Adapters::Output::Ui::Components::Screens::AnnotationsScreenComponent)
    end
  end

  describe 'key classification via DI' do
    let(:container) { Shoko::Application::ContainerFactory.create_default_container }
    let(:menu) { described_class.new(container) }

    it 'does not include adapter key definitions directly' do
      # Key classification is now handled via DI (:key_classifier port)
      expect(menu.class.included_modules).not_to include(Shoko::Adapters::Input::KeyDefinitions::Helpers)
    end
  end
end
