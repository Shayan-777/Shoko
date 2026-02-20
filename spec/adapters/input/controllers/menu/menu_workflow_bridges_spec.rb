# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::MenuWorkflowRuntimeBridge do
  let(:menu) { instance_double('MenuController', draw_screen: nil) }
  let(:catalog) { instance_double('Catalog', start_scan: nil) }

  subject(:bridge) do
    described_class.new(
      menu: menu,
      catalog: catalog
    )
  end

  it 'delegates draw_screen to menu controller' do
    bridge.draw_screen

    expect(menu).to have_received(:draw_screen).once
  end

  it 'delegates refresh_scan to catalog scanner' do
    bridge.refresh_scan(force: true)

    expect(catalog).to have_received(:start_scan).with(force: true).once
  end
end
