# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::MouseRouter do
  let(:registry) { Shoko::Adapters::Ui::State::MenuHitRegistry.new }
  let(:menu_state_reader) do
    instance_double(
      Shoko::Adapters::Runtime::SessionState::MenuSnapshotProjectionAdapter,
      mode: :menu, selected: 0, browse_selected: 0,
      rss_feeds: [{ key: '__all__', title: 'All Feeds' }, { key: 'f1', title: 'Daily' }],
      rss_articles: [{ id: 'a1', title: 'One' }],
      rss_selected_feed_key: '__all__', rss_selected_article_id: 'a1'
    )
  end
  let(:mutator) { instance_double(Shoko::Adapters::Runtime::SessionState::MenuSessionMutator, update_menu: nil) }
  let(:intent_handler) { instance_double(Shoko::Application::Ports::Inbound::MenuIntentHandler, handle_menu_intent: :handled) }
  let(:annotations_screen) { instance_double(Shoko::Adapters::Ui::Components::Screens::AnnotationsScreenComponent, selected: 1) }
  let(:main_menu_component) { instance_double(Shoko::Adapters::Ui::Components::MainMenuComponent, annotations_screen: annotations_screen) }

  subject(:router) do
    described_class.new(
      hit_registry: registry,
      menu_state_reader: menu_state_reader,
      menu_session_mutator: mutator,
      intent_handler: intent_handler,
      main_menu_component: main_menu_component
    )
  end

  def press_release(col, row)
    router.handle(button: 0, x: col - 1, y: row - 1, released: false)
    router.handle(button: 0, x: col - 1, y: row - 1, released: true)
  end

  it 'selects a rail entry on first click and activates it on the second (landing)' do
    registry.register(col: 1, row: 5, width: 24, height: 1, action: { type: :rail, index: 2 })
    press_release(5, 5)
    expect(mutator).to have_received(:update_menu).with(selected: 2)

    allow(menu_state_reader).to receive(:selected).and_return(2)
    press_release(5, 5)
    expect(intent_handler).to have_received(:handle_menu_intent).with(:activate_menu_selection, nil)
  end

  it 'jumps straight to a rail entry when clicked from inside a view' do
    allow(menu_state_reader).to receive(:mode).and_return(:browse)
    registry.register(col: 1, row: 6, width: 24, height: 1, action: { type: :rail, index: 4 })

    press_release(3, 6)

    expect(mutator).to have_received(:update_menu).with(selected: 4)
    expect(intent_handler).to have_received(:handle_menu_intent).with(:activate_menu_selection, nil)
  end

  it 'selects a list row on first click and activates on the click that lands on the selection' do
    allow(menu_state_reader).to receive(:mode).and_return(:browse)
    registry.register(col: 30, row: 4, width: 60, height: 2, action: { type: :list_row, list: :browse, index: 3 })

    press_release(40, 4)
    expect(mutator).to have_received(:update_menu).with(browse_selected: 3)

    allow(menu_state_reader).to receive(:browse_selected).and_return(3)
    press_release(40, 4)
    expect(intent_handler).to have_received(:handle_menu_intent).with(:open_selected_book, nil)
  end

  it 'routes wheel turns over a list to the matching move intents' do
    allow(menu_state_reader).to receive(:mode).and_return(:library)
    registry.register(col: 30, row: 4, width: 60, height: 10, action: { type: :list_wheel, list: :library })

    router.handle(button: 64, x: 40, y: 6, released: false)
    expect(intent_handler).to have_received(:handle_menu_intent)
      .with(:move_library_selection_up, having_attributes(delta: -1))

    router.handle(button: 65, x: 40, y: 6, released: false)
    expect(intent_handler).to have_received(:handle_menu_intent)
      .with(:move_library_selection_down, having_attributes(delta: 1))
  end

  it 'moves the landing selection when the wheel turns over the rail' do
    registry.register(col: 1, row: 1, width: 24, height: 20, action: { type: :rail_surface })

    router.handle(button: 65, x: 5, y: 8, released: false)

    expect(intent_handler).to have_received(:handle_menu_intent)
      .with(:move_menu_selection_down, having_attributes(delta: 1))
  end

  it 'scrolls the translator language picker under the wheel' do
    allow(menu_state_reader).to receive(:mode).and_return(:translator_source_dropdown)
    registry.register(col: 30, row: 10, width: 26, height: 7,
                      action: { type: :list_wheel, list: :translator_language })

    router.handle(button: 65, x: 35, y: 12, released: false)

    expect(intent_handler).to have_received(:handle_menu_intent)
      .with(:move_translator_language_selection_down, having_attributes(delta: 1))
  end

  it 'selects RSS rows by their stable key and activates on the selected row' do
    allow(menu_state_reader).to receive(:mode).and_return(:rss_reader)
    registry.register(col: 30, row: 5, width: 60, height: 1, action: { type: :list_row, list: :rss_feeds, index: 1 })

    press_release(40, 5)
    expect(mutator).to have_received(:update_menu).with(rss_selected_feed_key: 'f1')

    allow(menu_state_reader).to receive(:rss_selected_feed_key).and_return('f1')
    press_release(40, 5)
    expect(intent_handler).to have_received(:handle_menu_intent).with(:rss_reader_activate_selection, nil)
  end

  it 'drives annotation selection through the screen-local cursor' do
    allow(menu_state_reader).to receive(:mode).and_return(:annotations)
    allow(annotations_screen).to receive(:selected=)
    registry.register(col: 30, row: 5, width: 60, height: 2,
                      action: { type: :list_row, list: :annotations, index: 0 })

    press_release(40, 5)
    expect(annotations_screen).to have_received(:selected=).with(0)
  end

  it 'consumes every mouse event, including motion, and tracks the pointer' do
    expect(router.handle(button: 35, x: 10, y: 10, released: false)).to be(true)
    expect(registry.hover?(col: 11, row: 11, width: 1, height: 1)).to be(true)
    expect(intent_handler).not_to have_received(:handle_menu_intent)
  end
end
