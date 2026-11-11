defmodule GPUI.Test.Native.TextStyleTest do
  use GPUI.Test, native: [size: {120, 80}]

  defmodule TextView do
    use GPUI.View

    @impl GPUI.View
    def render(assigns) do
      ~GPUI"""
      <div id="box" style={assigns.box}>
        <text style={assigns.text}>hello world</text>
      </div>
      """
    end
  end

  test "native accepts decoration, italic and transform styles", %{ui: ui} do
    box = [underline: true, line_through: true, font_style: :italic]

    for transform <- [:uppercase, :lowercase, :capitalize, :none] do
      assert ^ui = render(ui, TextView, box: box, text: [text_transform: transform])
    end

    assert ^ui = render(ui, TextView, box: [font_style: :normal], text: [])
  end
end
