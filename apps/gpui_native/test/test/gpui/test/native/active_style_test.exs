defmodule GPUI.Test.Native.ActiveStyleTest do
  use GPUI.Test, native: [size: {120, 80}]

  defmodule ActiveView do
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

  test "native accepts active colour and opacity styles", %{ui: ui} do
    style = [
      active_background: {:rgb, 0x2563EB},
      active_color: {:rgb, 0xFFFFFF},
      active_border_color: {:rgb, 0x1D4ED8},
      active_opacity: 0.7
    ]

    assert ^ui = render(ui, ActiveView, style: style)
  end
end
