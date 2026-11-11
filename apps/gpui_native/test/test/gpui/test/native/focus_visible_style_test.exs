defmodule GPUI.Test.Native.FocusVisibleStyleTest do
  use GPUI.Test, native: [size: {120, 80}]

  defmodule FocusVisibleView do
    use GPUI.View

    @impl GPUI.View
    def render(assigns) do
      ~GPUI"""
      <div id="panel" style={assigns.style}>
        <button id="press">Press</button>
      </div>
      """
    end
  end

  test "native accepts focus-visible colour and opacity styles", %{ui: ui} do
    style = [
      focus_visible_background: {:rgb, 0x2563EB},
      focus_visible_color: {:rgb, 0xFFFFFF},
      focus_visible_border_color: {:rgb, 0x1D4ED8},
      focus_visible_opacity: 0.7
    ]

    assert ^ui = render(ui, FocusVisibleView, style: style)
  end
end
