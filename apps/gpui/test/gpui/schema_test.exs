defmodule GPUI.SchemaTest do
  use ExUnit.Case, async: true

  test "defines the neutral core schema independently" do
    assert GPUI.Schema.tags() == [
             :div,
             :button,
             :layer,
             :span,
             :scroll,
             :list,
             :item,
             :text_surface,
             :text_input,
             :img,
             :svg,
             :text,
             :ui_edge_fade,
             :ui_frost,
             :ui_paint
           ]

    assert :text_surface in GPUI.Schema.identified_tags()
    assert GPUI.Schema.component!(:text_surface).required_events == []
    assert Enum.map(GPUI.Schema.stateful_components(), & &1.kind) == [:text_surface]
    assert :raster in GPUI.Schema.resources()
    assert :border_radius in GPUI.Schema.styles()

    assert Enum.all?(
             [
               :border_top_left_radius,
               :border_top_right_radius,
               :border_bottom_left_radius,
               :border_bottom_right_radius
             ],
             &(&1 in GPUI.Schema.styles())
           )
    assert :font_weight in GPUI.Schema.styles()
    assert :font_family in GPUI.Schema.styles()

    assert Enum.all?(
             [:font_style, :underline, :line_through, :text_transform],
             &(&1 in GPUI.Schema.styles())
           )

    assert :box_shadow in GPUI.Schema.styles()

    assert Enum.all?(
             [
               :border_top_width,
               :border_bottom_width,
               :border_left_width,
               :border_right_width,
               :border_style
             ],
             &(&1 in GPUI.Schema.styles())
           )
  end

  test "retains neutral defaults and validation" do
    assert %{max_lines: 8, min_lines: 1} = GPUI.Schema.defaults(:text_surface)

    assert_raise ArgumentError, ~r/unknown GPUI component/, fn ->
      GPUI.Schema.component!(:unknown)
    end
  end

  describe "svg source" do
    test "accepts non-empty markup up to 1 MiB" do
      assert %{source: "<svg/>"} =
               GPUI.Schema.validate_component_assigns!(%{source: "<svg/>"}, :svg)

      limit = String.duplicate("a", 1_048_576)
      assert %{source: ^limit} = GPUI.Schema.validate_component_assigns!(%{source: limit}, :svg)
    end

    test "rejects empty, oversize and non-binary sources" do
      for source <- ["", String.duplicate("a", 1_048_577), :svg, 12] do
        assert_raise ArgumentError, ~r/svg.*source/, fn ->
          GPUI.Schema.validate_component_assigns!(%{source: source}, :svg)
        end
      end
    end
  end
end
