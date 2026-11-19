defmodule GPUI.Test.Native.ClipboardTest do
  use GPUI.Test, native: [size: {320, 240}]

  test "reads back the text that was written", %{ui: ui} do
    write_clipboard(ui, "copied text")
    assert read_clipboard(ui) == "copied text"
  end

  test "an empty string is written as empty text", %{ui: ui} do
    write_clipboard(ui, "previous")
    write_clipboard(ui, "")
    assert read_clipboard(ui) == ""
  end

  test "multi-line text keeps its line breaks", %{ui: ui} do
    text = "first\nsecond\r\n\nfourth ünïcode"
    write_clipboard(ui, text)
    assert read_clipboard(ui) == text
  end
end
