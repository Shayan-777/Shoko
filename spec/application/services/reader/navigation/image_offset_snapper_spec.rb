# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::Reader::Navigation::ImageOffsetSnapper do
  let(:layout_service) { instance_double(Shoko::Application::Services::LayoutService, calculate_metrics: [40, 18]) }
  let(:wrapped_lines_provider) { instance_double(Shoko::Application::Ports::Outbound::WrappedLinesProvider) }
  let(:terminal_size) { Struct.new(:width, :height).new(80, 24) }
  let(:config_store) do
    instance_double(
      Shoko::Application::Ports::Outbound::AppConfigStore,
      load: Shoko::Application::Ports::Outbound::State::ConfigSnapshot.build(kitty_images: true, view_mode: :single)
    )
  end
  let(:reader_session_store) { instance_double(Shoko::Application::Ports::Outbound::ReaderSessionStore) }
  let(:reader_state_reader) { instance_double(Shoko::Adapters::Runtime::SessionState::ReaderSnapshotProjectionAdapter, load: Shoko::Application::Ports::Outbound::State::ReaderPaginationSnapshot.build) }
  let(:display_capabilities) { instance_double(Shoko::Application::Ports::Outbound::DisplayCapabilities, kitty_images_enabled?: kitty_images_enabled) }
  let(:reader_runtime_context) do
    instance_double(Shoko::Application::Ports::Outbound::ReaderRuntimeContext, display_capabilities: display_capabilities, terminal_size: terminal_size)
  end
  let(:logger) { instance_double(Shoko::Application::Ports::Outbound::Logging, debug: nil) }
  let(:kitty_images_enabled) { true }
  let(:snapper) do
    described_class.new(
      layout_service: layout_service,
      wrapped_lines_provider: wrapped_lines_provider,
      app_config_store: config_store,
      reader_session_store: reader_session_store,
      reader_state_reader: reader_state_reader,
      reader_runtime_context: reader_runtime_context,
      logger: logger
    )
  end

  def display_line(metadata)
    Shoko::Application::Ports::Outbound::Formatting::DisplayLine.new(text: 'img', segments: [], metadata: metadata)
  end

  def single_layout_state(single_page: 2)
    Shoko::Application::Services::Reader::Navigation::AbsoluteLayout::LayoutState.new(
      snapshot: { current_chapter: 0, single_page: single_page },
      view_mode: :single,
      metrics: { single: 10, split: 5 },
      stride: 10
    )
  end

  def split_layout_state(left_page: 2)
    Shoko::Application::Services::Reader::Navigation::AbsoluteLayout::LayoutState.new(
      snapshot: { current_chapter: 0, left_page: left_page, right_page: left_page + 10 },
      view_mode: :split,
      metrics: { single: 10, split: 10 },
      stride: 10
    )
  end

  it 'snaps single-page absolute offsets back to the image render line' do
    lines = [
      display_line(image_render: { width: 10 }, image: { src: 'cover' }, image_render_line: true),
      display_line(image_render: { width: 10 }, image: { src: 'cover' }),
      display_line(image_render: { width: 10 }, image: { src: 'cover' }),
    ]
    allow(wrapped_lines_provider).to receive(:wrapped_lines_for).and_return(lines)

    result = snapper.snap({ current_chapter: 0, single_page: 2, current_page: 2 }, single_layout_state)

    expect(result).to include(single_page: 0, current_page: 0)
  end

  it 'snaps split-mode offsets and keeps left, right, and current page aligned' do
    lines = [
      display_line(image_render: { width: 10 }, image: { src: 'cover' }, image_render_line: true),
      display_line(image_render: { width: 10 }, image: { src: 'cover' }),
      display_line(image_render: { width: 10 }, image: { src: 'cover' }),
    ]
    allow(wrapped_lines_provider).to receive(:wrapped_lines_for).and_return(lines)

    result = snapper.snap({ current_chapter: 0, left_page: 2, current_page: 2, right_page: 12 }, split_layout_state)

    expect(result).to include(left_page: 0, current_page: 0, right_page: 10)
  end

  it 'treats string-key and symbol-key image metadata identically' do
    symbol_lines = [
      display_line(image_render: { width: 10 }, image: { src: 'cover' }, image_render_line: true),
      display_line(image_render: { width: 10 }, image: { src: 'cover' }),
      display_line(image_render: { width: 10 }, image: { src: 'cover' }),
    ]
    string_lines = [
      display_line('image_render' => { 'width' => 10 }, 'image' => { 'src' => 'cover' }, 'image_render_line' => true),
      display_line('image_render' => { 'width' => 10 }, 'image' => { 'src' => 'cover' }),
      display_line('image_render' => { 'width' => 10 }, 'image' => { 'src' => 'cover' }),
    ]
    allow(wrapped_lines_provider).to receive(:wrapped_lines_for).and_return(symbol_lines, string_lines)

    symbol_result = snapper.snap({ current_chapter: 0, single_page: 2, current_page: 2 }, single_layout_state)
    string_result = snapper.snap({ current_chapter: 0, single_page: 2, current_page: 2 }, single_layout_state)

    expect(string_result).to eq(symbol_result)
  end

  it 'returns unchanged updates when kitty images are disabled or wrapped lines are unavailable' do
    disabled_snapper = described_class.new(
      layout_service: layout_service,
      wrapped_lines_provider: wrapped_lines_provider,
      app_config_store: config_store,
      reader_session_store: reader_session_store,
      reader_state_reader: reader_state_reader,
      reader_runtime_context: instance_double(
        Shoko::Application::Ports::Outbound::ReaderRuntimeContext,
        display_capabilities: instance_double(Shoko::Application::Ports::Outbound::DisplayCapabilities, kitty_images_enabled?: false),
        terminal_size: terminal_size
      ),
      logger: logger
    )
    updates = { current_chapter: 0, single_page: 2, current_page: 2 }

    expect(disabled_snapper.snap(updates.dup, single_layout_state)).to eq(updates)

    allow(wrapped_lines_provider).to receive(:wrapped_lines_for).and_return(nil)

    expect(snapper.snap(updates.dup, single_layout_state)).to eq(updates)
  end

  it 'returns unchanged updates on typed failures and logs a debug event' do
    updates = { current_chapter: 0, single_page: 2, current_page: 2 }
    allow(wrapped_lines_provider).to receive(:wrapped_lines_for).and_raise(
      Shoko::StorageError.new('load', nil, 'broken lines')
    )
    allow(logger).to receive(:debug)

    result = snapper.snap(updates.dup, single_layout_state)

    expect(result).to eq(updates)
    expect(logger).to have_received(:debug).with(include('image_offset_snapper.snap_offset failed'))
  end
end
