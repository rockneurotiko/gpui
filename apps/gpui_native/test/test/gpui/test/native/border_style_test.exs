defmodule GPUI.Test.Native.BorderStyleTest do
  use GPUI.Test, native: [size: {120, 80}]

  defmodule BorderView do
    use GPUI.View

    @impl GPUI.View
    def render(assigns) do
      ~GPUI"""
      <div id="box" style={assigns.box}></div>
      """
    end
  end

  test "native accepts per-side border widths and dashed borders", %{ui: ui} do
    box = [
      border_bottom_width: {:px, 1.5},
      border_top_width: {:px, 2.0},
      border_left_width: {:px, 1.0},
      border_right_width: {:px, 1.0},
      border_color: {:rgb, 0xEF4444},
      border_style: :dashed
    ]

    assert ^ui = render(ui, BorderView, box: box)
    assert ^ui = render(ui, BorderView, box: [border_style: :solid])
  end
end
