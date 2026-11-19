defmodule GPUI.Test.Native.OpacityStyleTest do
  use GPUI.Test, native: [size: {120, 80}]

  defmodule OpacityView do
    use GPUI.View

    @impl GPUI.View
    def render(assigns) do
      ~GPUI"""
      <div id="outer" style={assigns.outer}>
        <button id="field" style={assigns.field} focus_request={1}>Field</button>
      </div>
      """
    end
  end

  test "native accepts hover, focus and focus-within opacity while focus moves", %{ui: ui} do
    field = [hover_opacity: 0.8, focus_opacity: 0.6]
    outer = [focus_within_opacity: 0.4]

    assert ^ui = render(ui, OpacityView, outer: outer, field: field)
    assert ^ui = focus(ui, "field")
  end
end
