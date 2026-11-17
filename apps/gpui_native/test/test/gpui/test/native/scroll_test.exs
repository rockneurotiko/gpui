defmodule GPUI.Test.Native.ScrollTest do
  use GPUI.Test, native: [size: {320, 240}]

  defmodule ObservedView do
    use GPUI.View

    @impl GPUI.View
    def render(_assigns) do
      ~GPUI"""
      <scroll id="feed" phx-scroll="feed_scrolled" class="h-[120px]">
        <div id="feed-content" class="h-[1200px]"><text>tall content</text></div>
      </scroll>
      """
    end
  end

  defmodule PlainView do
    use GPUI.View

    @impl GPUI.View
    def render(_assigns) do
      ~GPUI"""
      <scroll id="plain" class="h-[120px]">
        <div class="h-[1200px]"><text>tall content</text></div>
      </scroll>
      """
    end
  end

  defp offsets(acc \\ []) do
    receive do
      {:gpui, _ui, {:event, %{type: :scroll, event: "feed_scrolled", value: %{offset_y: y}}}} ->
        offsets([y | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "reports a non-negative offset that is zero at the top", %{ui: ui} do
    render(ui, ObservedView, %{})

    assert_receive {:gpui, ^ui,
                    {:event, %{type: :scroll, event: "feed_scrolled", value: %{offset_y: top}}}}

    assert top == +0.0
  end

  test "reports a positive offset after scrolling down", %{ui: ui} do
    render(ui, ObservedView, %{})
    assert [+0.0] = offsets()
    advance(ui, 60)

    scroll(ui, "feed", delta: {0, -100})

    assert [offset] = offsets()
    assert offset > 0
  end

  test "throttles a wheel burst and still delivers the final offset", %{ui: ui} do
    render(ui, ObservedView, %{})
    assert [+0.0] = offsets()
    advance(ui, 60)

    for _step <- 1..20, do: scroll(ui, "feed", delta: {0, -10})

    burst = offsets()
    assert [first] = burst
    assert first > 0

    advance(ui, 60)
    assert [final] = offsets()
    assert final > first
    assert final == -bounds(ui, "feed-content").y

    advance(ui, 200)
    assert offsets() == []
  end

  test "containers without the attribute emit nothing", %{ui: ui} do
    render(ui, PlainView, %{})
    scroll(ui, "plain", delta: {0, -100})
    advance(ui, 200)

    refute_receive {:gpui, ^ui, {:event, %{type: :scroll}}}, 50
  end

  test "scroll_to_top resets the offset and ignores unknown ids", %{ui: ui} do
    render(ui, ObservedView, %{})
    advance(ui, 60)
    offsets()

    scroll(ui, "feed", delta: {0, -100})
    assert [scrolled] = offsets()
    assert scrolled > 0
    advance(ui, 60)

    scroll_to_top(ui, "missing")
    advance(ui, 60)
    assert offsets() == []

    scroll_to_top(ui, "feed")
    advance(ui, 60)
    assert [+0.0] = offsets()
  end
end
