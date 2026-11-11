defmodule GPUI.TailwindTest do
  use ExUnit.Case, async: false

  setup do
    previous = Application.get_env(:gpui, :unknown_classes)
    Application.put_env(:gpui, :unknown_classes, :keep)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gpui, :unknown_classes, previous),
        else: Application.delete_env(:gpui, :unknown_classes)
    end)
  end

  test "normalizes text decoration, italic and transform classes" do
    assert %{style: style, unknown: []} =
             GPUI.Tailwind.normalize("italic underline line-through uppercase")

    assert Enum.sort(style) ==
             [
               font_style: :italic,
               line_through: true,
               text_transform: :uppercase,
               underline: true
             ]

    assert %{style: [font_style: :normal, text_transform: :none], unknown: []} =
             GPUI.Tailwind.normalize("italic not-italic capitalize normal-case")

    assert %{style: [], unknown: []} = GPUI.Tailwind.normalize("underline no-underline")
    assert %{unknown: ["tracking-wide"]} = GPUI.Tailwind.normalize("tracking-wide")
  end

  test "programmatic UI components normalize classes before serialization" do
    payload =
      GPUI.UI.tree_item(%{
        id: "file",
        class: "flex items-center px-2 truncate cursor-pointer unknown-class",
        style: [color: {:rgb, 0xFFFFFF}],
        children: ["long filename"]
      })
      |> GPUI.Element.to_payload()

    assert payload.attrs.class == "unknown-class"

    assert payload.attrs.style == [
             display: :flex,
             align_items: :center,
             padding_x: [:px, 8.0],
             truncate: true,
             cursor: :pointer,
             color: [:rgb, 0xFFFFFF]
           ]
  end

  test "normalizes font families" do
    for {class, family} <- [
          {"font-sans", "sans-serif"},
          {"font-serif", "serif"},
          {"font-mono", "monospace"},
          {"font-[Fira_Code]", "Fira Code"},
          {"font-['Fira_Code']", "Fira Code"},
          {"font-[family-name:Fira_Code]", "Fira Code"}
        ] do
      assert %{style: [font_family: ^family], unknown: []} = GPUI.Tailwind.normalize(class)
    end

    assert %{style: [], unknown: ["font-[Broken"]} = GPUI.Tailwind.normalize("font-[Broken")
    assert %{style: [], unknown: ["font-[650]"]} = GPUI.Tailwind.normalize("font-[650]")
    assert %{style: [], unknown: ["font-[1000]"]} = GPUI.Tailwind.normalize("font-[1000]")
  end

  test "normalizes the full font weight scale" do
    for {class, weight} <- [
          {"font-thin", :thin},
          {"font-extralight", :extra_light},
          {"font-light", :light},
          {"font-normal", :normal},
          {"font-medium", :medium},
          {"font-semibold", :semibold},
          {"font-bold", :bold},
          {"font-extrabold", :extra_bold},
          {"font-black", :black},
          {"font-[100]", :thin},
          {"font-[200]", :extra_light},
          {"font-[300]", :light},
          {"font-[400]", :normal},
          {"font-[500]", :medium},
          {"font-[600]", :semibold},
          {"font-[700]", :bold},
          {"font-[800]", :extra_bold},
          {"font-[900]", :black}
        ] do
      assert %{style: [font_weight: ^weight], unknown: []} = GPUI.Tailwind.normalize(class)
    end
  end

  test "normalizes a useful Tailwind subset" do
    assert %{
             style: [
               display: :flex,
               flex_direction: :column,
               align_items: :center,
               justify_content: :center,
               background: {:rgb, 0x404040},
               color: {:rgb, 0xFFFFFF},
               font_size: {:px, 20.0},
               width: {:px, 500.0},
               height: {:px, 500.0},
               gap: {:px, 12.0}
             ],
             unknown: []
           } =
             GPUI.Tailwind.normalize(
               "flex flex-col items-center justify-center bg-neutral-700 text-white text-xl size-[500px] gap-3"
             )
  end

  test "normalizes positioned layout and explicit insets" do
    assert %{
             style: [
               position: :relative,
               inset_x: {:fraction, 0.5},
               top: {:px, 8.0},
               right: :auto,
               bottom: {:px, 12.0},
               left: {:px, 18.0},
               margin_top: {:px, 4.0}
             ],
             unknown: []
           } =
             GPUI.Tailwind.normalize(
               "relative inset-x-1/2 top-2 right-auto bottom-3 left-[18px] mt-1"
             )

    assert %{style: style, unknown: []} =
             GPUI.Tailwind.normalize("absolute inset-0 -top-2 left-[-6px]")

    assert style == [
             position: :absolute,
             inset: {:px, 0},
             top: {:px, -8.0},
             left: {:px, -6.0}
           ]
  end

  test "normalizes full and fractional dimensions as relative native lengths" do
    assert %{
             style: [
               width: :full,
               height: :full,
               min_width: {:fraction, 0.5},
               max_height: {:fraction, 0.6666666666666666}
             ],
             unknown: []
           } = GPUI.Tailwind.normalize("w-full h-full min-w-1/2 max-h-2/3")
  end

  test "normalizes flex shorthand with native GPUI semantics" do
    assert %{
             style: [flex: :one, display: :flex],
             unknown: []
           } = GPUI.Tailwind.normalize("flex-1 flex")

    for {class, value} <- [
          {"flex-auto", :auto},
          {"flex-initial", :initial},
          {"flex-none", :none}
        ] do
      assert %{style: [flex: ^value], unknown: []} = GPUI.Tailwind.normalize(class)
    end
  end

  test "normalizes flex basis using lengths and auto" do
    assert %{style: style, unknown: []} =
             GPUI.Tailwind.normalize("basis-0 w-24 h-60 min-w-0 max-h-64")

    assert Keyword.fetch!(style, :flex_basis) == {:px, 0.0}
    assert Keyword.fetch!(style, :width) == {:px, 96.0}
    assert Keyword.fetch!(style, :height) == {:px, 240.0}
    assert Keyword.fetch!(style, :min_width) == {:px, 0.0}
    assert Keyword.fetch!(style, :max_height) == {:px, 256.0}

    for {class, expected} <- [
          {"basis-auto", :auto},
          {"basis-full", :full},
          {"basis-1/2", {:fraction, 0.5}},
          {"basis-[240px]", {:px, 240.0}}
        ] do
      assert %{style: [flex_basis: ^expected], unknown: []} = GPUI.Tailwind.normalize(class)
    end
  end

  test "normalizes clipping and dense text behavior" do
    assert %{
             style: [
               overflow: :hidden,
               white_space: :nowrap,
               text_overflow: :ellipsis,
               text_align: :right,
               truncate: true
             ],
             unknown: []
           } =
             GPUI.Tailwind.normalize(
               "overflow-hidden whitespace-nowrap text-ellipsis text-right truncate"
             )

    assert %{style: [white_space: :normal, text_align: :left], unknown: ["text-clip"]} =
             GPUI.Tailwind.normalize("whitespace-normal text-left text-clip")
  end

  test "normalizes native cursor behavior" do
    for {class, expected} <- [
          {"cursor-default", :default},
          {"cursor-pointer", :pointer},
          {"cursor-text", :text},
          {"cursor-move", :move},
          {"cursor-not-allowed", :not_allowed}
        ] do
      assert %{style: [cursor: ^expected], unknown: []} = GPUI.Tailwind.normalize(class)
    end
  end

  test "normalizes numeric scales and safe arbitrary values" do
    assert %{
             style: [
               gap: {:px, 6.0},
               padding: {:px, 28.0},
               width: {:px, 500.0},
               height: {:fraction, 0.5},
               font_size: {:px, 13.0},
               line_height: {:px, 18.0},
               opacity: 0.65,
               background: {:rgb, 0x101828},
               color: {:rgb, 0x94A3B8},
               border_radius: {:px, 5.0}
             ],
             unknown: []
           } =
             GPUI.Tailwind.normalize(
               "gap-1.5 p-7 w-[500px] h-[50%] text-[13px] leading-[18px] " <>
                 "opacity-[0.65] bg-[#101828] text-[#94a3b8] rounded-[5px]"
             )
  end

  test "normalizes the complete pinned Tailwind palette" do
    assert GPUI.Tailwind.Palette.tailwind_version() == "3.4.17"
    assert map_size(GPUI.Tailwind.Palette.colors()) == 245

    for family <-
          ~w(slate gray zinc neutral stone red orange amber yellow lime green emerald teal cyan sky blue indigo violet purple fuchsia pink rose),
        shade <- ~w(50 100 200 300 400 500 600 700 800 900 950) do
      assert {:ok, {:rgb, rgb}} = GPUI.Tailwind.Palette.fetch("#{family}-#{shade}")
      assert rgb in 0..0xFFFFFF
    end

    assert GPUI.Tailwind.Palette.fetch!("slate-950") == {:rgb, 0x020617}
    assert GPUI.Tailwind.Palette.fetch!("white") == {:rgb, 0xFFFFFF}
    assert GPUI.Tailwind.Palette.fetch!("transparent") == {:rgba, 0x00000000}
  end

  test "normalizes named colors with deterministic alpha modifiers" do
    assert %{style: style, unknown: []} =
             GPUI.Tailwind.normalize("bg-black/40 text-slate-300/70 border-white/5")

    assert style == [
             background: {:rgba, 0x00000066},
             color: {:rgba, 0xCBD5E1B3},
             border_color: {:rgba, 0xFFFFFF0D}
           ]
  end

  test "normalizes bounded arbitrary RGB and RGBA colors" do
    assert %{style: style, unknown: []} =
             GPUI.Tailwind.normalize("bg-[#abc] text-[#abcd] border-[#0f172a] bg-[#0f172acc]/80")

    assert style == [
             color: {:rgba, 0xAABBCCDD},
             border_color: {:rgb, 0x0F172A},
             background: {:rgba, 0x0F172AA3}
           ]
  end

  test "preserves malformed color classes" do
    classes =
      "bg-red-500/101 text-slate-300/-1 border-white/foo bg-[#12] text-[#xyz] " <>
        "border-[#0f172a]extra bg-not-a-color"

    assert %{style: [], unknown: unknown} = GPUI.Tailwind.normalize(classes)
    assert unknown == String.split(classes)
  end

  test "normalizes colors used by the counter example" do
    assert %{style: [background: {:rgb, 0x0F172A}], unknown: []} =
             GPUI.Tailwind.normalize("bg-slate-900")

    assert %{style: [background: {:rgb, 0x2563EB}], unknown: []} =
             GPUI.Tailwind.normalize("bg-blue-600")
  end

  test "normalizes expanded layout, typography, and box styles" do
    assert %{style: style, unknown: []} =
             GPUI.Tailwind.normalize(
               "grid flex-row-reverse flex-wrap grow shrink-0 items-stretch justify-between " <>
                 "font-semibold leading-tight opacity-75 px-4 mb-2 min-w-10 max-h-12 " <>
                 "border border-red-500"
             )

    assert style == [
             display: :grid,
             flex_direction: :row_reverse,
             flex_wrap: :wrap,
             flex_grow: 1.0,
             flex_shrink: 0.0,
             align_items: :stretch,
             justify_content: :between,
             font_weight: :semibold,
             line_height: {:px, 20.0},
             opacity: 0.75,
             padding_x: {:px, 16.0},
             margin_bottom: {:px, 8.0},
             min_width: {:px, 40.0},
             max_height: {:px, 48.0},
             border_width: {:px, 1.0},
             border_color: {:rgb, 0xEF4444}
           ]
  end

  test "per-side border widths and border style" do
    assert %{style: style, unknown: []} =
             GPUI.Tailwind.normalize(
               "border-b border-t-2 border-l-[1.5px] border-x-4 border-dashed"
             )

    assert style == [
             border_bottom_width: {:px, 1.0},
             border_top_width: {:px, 2.0},
             border_left_width: {:px, 4.0},
             border_right_width: {:px, 4.0},
             border_style: :dashed
           ]

    assert %{style: [border_style: :solid, border_color: {:rgb, 0xEF4444}], unknown: []} =
             GPUI.Tailwind.normalize("border-solid border-red-500")

    assert %{style: [border_color: _], unknown: []} =
             GPUI.Tailwind.normalize("border-transparent")

    assert %{unknown: ["border-t-3"]} = GPUI.Tailwind.normalize("border-t-3")
  end

  test "normalizes focus and focus-within colours" do
    assert %{
             style: [
               focus_background: {:rgb, 0x3B82F6},
               focus_color: {:rgb, 0xFFFFFF},
               focus_border_color: {:rgb, 0xEF4444},
               focus_within_background: {:rgb, 0x0F172A},
               focus_within_color: {:rgb, 0xFFFFFF},
               focus_within_border_color: {:rgb, 0xEF4444}
             ],
             unknown: []
           } =
             GPUI.Tailwind.normalize(
               "focus:bg-blue-500 focus:text-white focus:border-red-500 " <>
                 "focus-within:bg-slate-900 focus-within:text-white focus-within:border-red-500"
             )

    assert %{unknown: ["focus:bg-nope"]} = GPUI.Tailwind.normalize("focus:bg-nope")
  end

  test "every normalized style is supported by the native schema" do
    classes =
      "flex block grid hidden flex-col-reverse flex-wrap grow shrink-0 items-baseline " <>
        "justify-evenly font-bold leading-normal opacity-50 p-2 px-3 mt-1 w-full h-full " <>
        "min-w-6 max-h-8 border border-blue-500 rounded-lg bg-slate-900 text-white " <>
        "hover:bg-blue-500 focus:bg-blue-500 focus-within:text-white"

    assert %{style: styles} = GPUI.Tailwind.normalize(classes)
    assert Enum.all?(Keyword.keys(styles), &(&1 in GPUI.Schema.styles()))
  end

  test "preserves unsupported classes exactly" do
    assert %{
             style: [display: :flex],
             unknown: ["group-hover:bg-blue-500", "w-[calc(100%-1rem)]", "mx-auto"]
           } = GPUI.Tailwind.normalize("flex group-hover:bg-blue-500 w-[calc(100%-1rem)] mx-auto")
  end

  test "normalizes box shadows" do
    assert shadow("shadow-none") == []
    assert shadow("shadow-sm") == [{0.0, 1.0, 2.0, 0.0, {:rgba, 13}, false}]
    assert [_, {+0.0, 1.0, 2.0, -1.0, {:rgba, 26}, false}] = shadow("shadow")
    assert shadow("shadow-2xl") == [{0.0, 25.0, 50.0, -12.0, {:rgba, 64}, false}]
    assert shadow("shadow-inner") == [{0.0, 2.0, 4.0, 0.0, {:rgba, 13}, true}]

    for name <- ~w(2xs xs md lg xl), do: assert([_ | _] = shadow("shadow-#{name}"))
  end

  test "normalizes arbitrary box shadows" do
    assert shadow("shadow-[0_1px_2px_#11223344]") ==
             [{0.0, 1.0, 2.0, 0.0, {:rgba, 0x11223344}, false}]

    assert shadow("shadow-[1_-2.5px_3px_4px_#f00]") ==
             [{1.0, -2.5, 3.0, 4.0, {:rgba, 0xFF0000FF}, false}]

    assert shadow("shadow-[0_1px_2px_rgba(0,0,0,0.1),inset_0_0_0_1px_rgb(1,2,3,50%)]") == [
             {0.0, 1.0, 2.0, 0.0, {:rgba, 0x0000001A}, false},
             {0.0, 0.0, 0.0, 1.0, {:rgba, 0x01020380}, true}
           ]

    for class <-
          ~w(shadow-red-500 shadow-[0_1px] shadow-[0_1px_2px_nope] shadow-[0_-1px_-2px_#000] shadow-[0_1px_2px_#000 shadow-[]) do
      assert %{style: [], unknown: [^class]} = GPUI.Tailwind.normalize(class)
    end
  end

  defp shadow(class), do: GPUI.Tailwind.normalize(class).style[:box_shadow]
end
