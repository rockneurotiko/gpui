defmodule GPUI.Test.Native.FocusStyleTest do
  use GPUI.Test, native: [size: {120, 80}]

  defmodule FocusView do
    use GPUI.View

    @impl GPUI.View
    def render(assigns) do
      ~GPUI"""
      <div id="outer" style={assigns.outer}>
        <button id="field" style={assigns.field} focus_request={1}>Field</button>
        <div id="plain" style={assigns.field}></div>
      </div>
      """
    end
  end

  test "native applies focus and focus-within colours while focus moves", %{ui: ui} do
    field = [
      focus_background: {:rgb, 0x1D4ED8},
      focus_color: {:rgb, 0xFFFFFF},
      focus_border_color: {:rgb, 0x60A5FA},
      border_width: {:px, 1.0}
    ]

    outer = [
      focus_within_background: {:rgb, 0x0F172A},
      focus_within_color: {:rgb, 0xF8FAFC},
      focus_within_border_color: {:rgb, 0x38BDF8}
    ]

    assert ^ui = render(ui, FocusView, outer: outer, field: field)
    assert ^ui = focus(ui, "field")
    assert ^ui = focus(ui, "field")
  end
end
