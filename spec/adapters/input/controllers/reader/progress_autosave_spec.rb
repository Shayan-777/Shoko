# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Reader::ProgressAutosave do
  let(:fake_clock) do
    clock = Object.new
    clock.instance_variable_set(:@now, 100.0)
    clock.define_singleton_method(:monotonic_now) { @now }
    clock.define_singleton_method(:advance) { |seconds| @now += seconds }
    clock
  end

  let(:controller) do
    saves = []
    recorder = Object.new
    recorder.define_singleton_method(:save_progress) { saves << :saved }
    recorder.define_singleton_method(:saves) { saves }
    recorder
  end

  def build_autosave(min_interval: 2.0)
    described_class.new(controller: controller, clock: fake_clock, min_interval: min_interval)
  end

  it 'saves immediately on every chapter change' do
    autosave = build_autosave

    autosave.note_chapter_change
    autosave.note_chapter_change

    expect(controller.saves.length).to eq(2)
  end

  it 'throttles page-position saves to the configured interval' do
    autosave = build_autosave(min_interval: 2.0)

    autosave.note_position_change
    fake_clock.advance(0.5)
    autosave.note_position_change
    fake_clock.advance(0.5)
    autosave.note_position_change

    expect(controller.saves.length).to eq(1)

    fake_clock.advance(1.5)
    autosave.note_position_change

    expect(controller.saves.length).to eq(2)
  end

  it 'lets a chapter change reset the throttle window' do
    autosave = build_autosave(min_interval: 2.0)

    autosave.note_position_change
    fake_clock.advance(0.5)
    autosave.note_chapter_change

    expect(controller.saves.length).to eq(2)

    autosave.note_position_change
    expect(controller.saves.length).to eq(2)
  end
end
