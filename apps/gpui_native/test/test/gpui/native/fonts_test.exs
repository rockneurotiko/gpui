defmodule GPUI.Native.FontsTest do
  use ExUnit.Case, async: true

  @moduletag :native

  @font Path.expand("../../../support/fonts/KaTeX_Caligraphic-Regular.ttf", __DIR__)

  test "font data is accepted repeatedly without error" do
    assert {:ok, runtime} = GPUI.Native.Backend.start_runtime()
    data = File.read!(@font)

    assert {:ok, :ok} = GPUI.Native.Backend.load_fonts(runtime, [data])
    assert {:ok, :ok} = GPUI.Native.Backend.load_fonts(runtime, [data])
    assert {:ok, :ok} = GPUI.Native.Backend.stop_runtime(runtime)
  end
end
