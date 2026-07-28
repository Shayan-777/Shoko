# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::Menu::Actions::TranslatorPacks do
  let(:session_store_class) do
    Class.new do
      include Shoko::Application::Ports::Outbound::MenuSessionStore

      def initialize(snapshot) = @snapshot = snapshot
      def load = @snapshot
      def save(snapshot) = @snapshot = snapshot
    end
  end
  let(:transient_store_class) do
    Class.new do
      include Shoko::Application::Ports::Outbound::MenuTransientStore

      def initialize(snapshot) = @snapshot = snapshot
      def load = @snapshot
      def save(snapshot) = @snapshot = snapshot
    end
  end
  let(:entry) do
    {
      from: 'en', to: 'de', version: '2.0', size: 100,
      installed: true, installed_version: '1.0', update_available: false,
    }
  end
  let(:action_count) do
    Shoko::Application::Ports::Inbound::MenuCatalog.translator_packs_action_items.length
  end
  let(:session_store) do
    session_store_class.new(
      Shoko::Application::Ports::Outbound::State::MenuSessionSnapshot.build(
        mode: :translator_packs,
        translator_packs_selected: action_count
      )
    )
  end
  let(:transient_store) do
    transient_store_class.new(
      Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot.build(
        translator_packs_results: [entry],
        translator_packs_status: :done
      )
    )
  end
  let(:workflow) { double('TranslatorPacksWorkflow', fetch_pack_catalog: nil, download_pack: nil) }
  let(:settings) { double('SettingsService', toggle_translator_backend: nil) }

  subject(:action) do
    described_class.new(
      menu_session_store: session_store,
      menu_transient_store: transient_store,
      translator_packs_workflow: workflow,
      settings_service: settings
    )
  end

  def menu
    Shoko::Application::Ports::Outbound::State::MenuSnapshot.build(
      session_store.load.to_h.merge(transient_store.load.to_h)
    )
  end

  it 'requires a second activation before removing an installed pack' do
    action.call(:activate_translator_packs_selection)

    expect(workflow).not_to have_received(:download_pack)
    expect(menu.translator_packs_pending_remove).to eq('en-de')
    expect(menu.translator_packs_message).to include('Press Enter again')

    action.call(:activate_translator_packs_selection)

    expect(workflow).to have_received(:download_pack).with(hash_including(from: 'en', to: 'de'))
    expect(menu.translator_packs_pending_remove).to be_nil
  end

  it 'installs an available update without treating it as removal' do
    transient_store.save(
      transient_store.load.with(
        translator_packs_results: [entry.merge(update_available: true)]
      )
    )

    action.call(:activate_translator_packs_selection)

    expect(workflow).to have_received(:download_pack).once
    expect(menu.translator_packs_pending_remove).to be_nil
  end

  it 'ignores repeated activation while a pack operation is active' do
    transient_store.save(transient_store.load.with(translator_packs_status: :downloading))

    action.call(:activate_translator_packs_selection)

    expect(workflow).not_to have_received(:download_pack)
  end
end
