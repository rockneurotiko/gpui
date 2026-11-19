defmodule GPUI.Test.Native.FormStyleTest do
  use GPUI.Test, native: [size: {400, 240}]

  defmodule FieldsView do
    use GPUI.View

    @impl GPUI.View
    def render(_assigns) do
      ~GPUI"""
      <div class="flex flex-col gap-4 w-[400px]">
        <GPUI.UI.select
          id="first"
          label="First"
          value="a"
          options={[%{label: "A", value: "a"}]}
          class="w-[260px] h-[36px] rounded-[7px] border border-[#334155]"
          phx-change="changed"
        />
        <GPUI.UI.select
          id="second"
          label="Second"
          value="a"
          options={[%{label: "A", value: "a"}]}
          class="w-[260px] h-[36px] rounded-[7px] border border-[#334155]"
          phx-change="changed"
        />
        <GPUI.UI.input
          id="name"
          label="Name"
          value="Ada"
          class="w-[260px] h-[36px] rounded-[7px] border border-[#334155]"
          phx-change="changed"
        />
      </div>
      """
    end
  end

  test "select and input honour width and height from class", %{ui: ui} do
    render(ui, FieldsView, [])
    settle(ui)

    for id <- ["first", "second", "name"] do
      assert %{width: 260.0, height: 36.0} = bounds(ui, id)
    end
  end
end
