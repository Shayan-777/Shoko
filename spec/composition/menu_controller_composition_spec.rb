# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

# Builds the menu controller from the real container, the way bin/shoko does.
#
# Every other menu spec injects doubles, so a field missing from a composition
# context — or a screen factory that was never defined — passes the whole suite
# and then crashes on launch. This is the spec that would have caught exactly
# that: the RSS text-interaction work added services to the menu context and a
# lookup screen to the registry, and both gaps were invisible until the binary
# was run by hand.
RSpec.describe 'Menu controller composition' do
  around do |example|
    Dir.mktmpdir do |dir|
      SpecEnvHelpers.instance_method(:with_env).bind_call(
        self,
        'XDG_CONFIG_HOME' => File.join(dir, 'config'),
        'XDG_CACHE_HOME' => File.join(dir, 'cache'),
        'XDG_DATA_HOME' => File.join(dir, 'data')
      ) { example.run }
    end
  end

  let(:container) { Shoko::Composition::ContainerFactory.create_default_container(log_config: {}) }
  let(:menu) { Shoko::Composition::ContainerFactory.send(:build_menu_controller, container) }
  let(:main_menu_component) { menu.instance_variable_get(:@main_menu_component) }

  it 'builds the whole menu controller graph' do
    expect(menu).to be_a(Shoko::Adapters::Input::Controllers::Menu::Controller)
  end

  # A mode with no screen leaves the menu on a stale view or raises; every mode
  # the input controller can enter must therefore resolve to a component.
  it 'resolves every registered menu mode to a screen' do
    modes = Shoko::Adapters::Ui::Components::MainMenuComponent::SCREEN_FOR_MODE.keys +
            Shoko::Adapters::Ui::Components::MainMenuComponent::MODE_TO_RAIL_KEY.keys

    modes.uniq.each do |mode|
      main_menu_component.state_changed(nil, nil, mode)

      expect(main_menu_component.instance_variable_get(:@current_screen)).not_to be_nil,
                                                                                "mode #{mode.inspect} has no screen"
    end
  end

  it 'gives the RSS reading pane its own screen and the lookup view its own' do
    main_menu_component.state_changed(nil, nil, :rss_reader)
    reading = main_menu_component.instance_variable_get(:@current_screen)
    main_menu_component.state_changed(nil, nil, :rss_reader_lookup)
    lookup = main_menu_component.instance_variable_get(:@current_screen)

    expect(reading).to be_a(Shoko::Adapters::Ui::Components::Screens::RssReaderScreenComponent)
    expect(lookup).to be_a(Shoko::Adapters::Ui::Components::Screens::RssLookupScreenComponent)
  end

  # The reading pane's actions need these collaborators. The workflow is built
  # lazily, so it is resolved here — which is also what proves the composition
  # context actually carries the fields the builder asks it for.
  it 'supplies the RSS workflow with the services its text actions need' do
    workflow = menu.instance_variable_get(:@state_controller)
                   .instance_variable_get(:@rss_reader_workflow).__target__

    %i[@clipboard @dictionary_service @annotation_service].each do |field|
      expect(workflow.instance_variable_get(field)).not_to be_nil, "workflow is missing #{field}"
    end
  end

  it 'builds the reading-pane mouse handler' do
    expect(menu.instance_variable_get(:@rss_reading_mouse_handler))
      .to be_a(Shoko::Adapters::Input::Controllers::Menu::RssReadingMouseHandler)
  end
end
