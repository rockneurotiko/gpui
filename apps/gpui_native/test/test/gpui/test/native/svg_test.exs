defmodule GPUI.Test.Native.SvgTest do
  use GPUI.Test, native: [size: {120, 80}]

  @icon ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M2 2h20v20H2z"/></svg>)

  defmodule IconView do
    use GPUI.View

    @impl GPUI.View
    def render(assigns) do
      ~GPUI"""
      <div class="flex flex-col items-start">
        <div id="frame">
        <svg
          class="w-6 h-4 text-white hover:text-[#38bdf8] focus:text-[#38bdf8] focus-within:text-[#38bdf8]"
          source={assigns.source}
          label="Square"
        />
        </div>
      </div>
      """
    end
  end

  test "native accepts a tinted svg and lays it out from its size classes", %{ui: ui} do
    assert ^ui = render(ui, IconView, source: @icon)
    settle(ui)

    assert %{width: 24.0, height: 16.0} = bounds(ui, "frame")
  end
end
