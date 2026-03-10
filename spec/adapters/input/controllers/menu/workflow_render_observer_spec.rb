# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::WorkflowRenderObserver do
  let(:menu) { instance_double('MenuController', draw_screen: nil) }
  let(:clock) { instance_double('Clock') }

  subject(:observer) { described_class.new(menu: menu, clock: clock, logger: nil) }

  it 'redraws immediately for forced workflow state changes' do
    allow(clock).to receive(:monotonic_now).and_return(1.0)

    observer.state_changed(%i[menu download_status], :idle, :downloading)

    expect(menu).to have_received(:draw_screen).once
  end

  it 'throttles progress redraw requests for high-frequency updates' do
    allow(clock).to receive(:monotonic_now).and_return(1.0, 1.02, 1.08)

    observer.state_changed(%i[menu download_progress], 0.0, 0.1)
    observer.state_changed(%i[menu download_progress], 0.1, 0.2)
    observer.state_changed(%i[menu download_progress], 0.2, 0.3)

    expect(menu).to have_received(:draw_screen).twice
  end

  it 'ignores unrelated state changes' do
    observer.state_changed(%i[menu browse_selected], 0, 1)

    expect(menu).not_to have_received(:draw_screen)
  end
end
