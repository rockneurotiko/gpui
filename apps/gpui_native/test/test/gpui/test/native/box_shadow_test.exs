defmodule GPUI.Test.Native.BoxShadowTest do
  use GPUI.Test, native: [size: {120, 80}]

  defmodule ShadowView do
    use GPUI.View

    @impl GPUI.View
    def render(assigns) do
      ~GPUI"""
      <div id="card" style={[width: {:px, 40}, height: {:px, 20}, box_shadow: assigns.shadow]}>
        <text>card</text>
      </div>
      """
    end
  end

  @shadows [
    {{:px, 0.0}, {:px, 1.0}, {:px, 2.0}, {:px, 0.0}, {:rgba, 0x0000001A}, false},
    {{:px, 0.0}, {:px, 0.0}, {:px, 0.0}, {:px, 1.0}, {:rgb, 0xFF0000}, true}
  ]

  test "native accepts box shadow lists, including the empty list", %{ui: ui} do
    assert ^ui = render(ui, ShadowView, shadow: @shadows)
    assert ^ui = render(ui, ShadowView, shadow: [])
  end

  test "native rejects a shadow with a non-boolean inset", %{ui: ui} do
    shadow = [{{:px, 0.0}, {:px, 1.0}, {:px, 2.0}, {:px, 0.0}, {:rgba, 0}, :yes}]

    assert %GPUI.Test.NativeError{reason: {{:badarg, _}, _}} =
             catch_error(render(ui, ShadowView, shadow: shadow))
  end

  test "native rejects a shadow that is not a tuple", %{ui: ui} do
    assert %GPUI.Test.NativeError{reason: {{:badarg, _}, _}} =
             catch_error(render(ui, ShadowView, shadow: [:bad]))
  end
end
