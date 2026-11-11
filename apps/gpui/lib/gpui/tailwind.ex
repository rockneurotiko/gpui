defmodule GPUI.Tailwind do
  @moduledoc """
  Small Tailwind-compatible class normalizer for GPUI element styles.

  This intentionally starts with a constrained subset that maps cleanly to GPUI.
  Unknown classes are preserved under `:class` by callers and handled according
  to the `:unknown_classes` application setting: `:warn` (the development
  default), `:error`, or `:keep`.
  """

  @cache_table __MODULE__.Cache
  @cache_limit 4_096
  @spacing_unit 4.0

  @text_sizes %{
    "xs" => 12.0,
    "sm" => 14.0,
    "base" => 16.0,
    "lg" => 18.0,
    "xl" => 20.0,
    "2xl" => 24.0,
    "3xl" => 30.0
  }

  @line_heights %{
    "none" => 16.0,
    "tight" => 20.0,
    "snug" => 22.0,
    "normal" => 24.0,
    "relaxed" => 26.0,
    "loose" => 32.0
  }

  @type result :: %{style: keyword(), unknown: [String.t()]}

  @spec normalize(String.t() | [String.t()] | nil) :: result()
  def normalize(nil), do: %{style: [], unknown: []}

  def normalize(classes) when is_list(classes) do
    classes
    |> Enum.join(" ")
    |> normalize()
  end

  def normalize(classes) when is_binary(classes) do
    case cached(classes) do
      {:ok, result} -> result
      :error -> cache(classes, normalize_binary(classes))
    end
  end

  @doc "Applies the configured warning or error policy to unsupported classes."
  @spec handle_unknown!([String.t()]) :: :ok
  def handle_unknown!([]), do: :ok

  def handle_unknown!(classes) when is_list(classes) do
    case Application.get_env(:gpui, :unknown_classes, default_unknown_class_policy()) do
      :keep ->
        :ok

      :warn ->
        require Logger
        Logger.warning("unsupported GPUI classes: #{Enum.join(classes, ", ")}")

      :error ->
        raise ArgumentError, "unsupported GPUI classes: #{Enum.join(classes, ", ")}"

      policy ->
        raise ArgumentError,
              "expected :gpui, :unknown_classes to be :keep, :warn, or :error; got: #{inspect(policy)}"
    end
  end

  defp default_unknown_class_policy do
    if Code.ensure_loaded?(Mix) and Mix.env() == :dev, do: :warn, else: :keep
  end

  defp normalize_binary(classes) do
    classes
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reduce(%{style: [], unknown: []}, &normalize_class/2)
    |> Map.update!(:style, &Enum.reverse/1)
    |> Map.update!(:unknown, &Enum.reverse/1)
  end

  defp cached(classes) do
    table = ensure_cache()

    case :ets.lookup(table, classes) do
      [{^classes, result}] -> {:ok, result}
      [] -> :error
    end
  end

  defp cache(classes, result) do
    table = ensure_cache()
    if :ets.info(table, :size) < @cache_limit, do: :ets.insert(table, {classes, result})
    result
  end

  defp ensure_cache do
    case :ets.whereis(@cache_table) do
      :undefined -> new_cache()
      table -> table
    end
  end

  defp new_cache do
    :ets.new(@cache_table, [:named_table, :set, :public, read_concurrency: true])
  rescue
    ArgumentError -> :ets.whereis(@cache_table)
  end

  @arbitrary_weights %{
    "100" => :thin,
    "200" => :extra_light,
    "300" => :light,
    "400" => :normal,
    "500" => :medium,
    "600" => :semibold,
    "700" => :bold,
    "800" => :extra_bold,
    "900" => :black
  }

  # `font-[600]` is an arbitrary weight, not a family; other digit-only names are unknown.
  defp font_family(acc, name, class) do
    name = name |> String.replace_prefix("family-name:", "") |> String.trim("'")

    cond do
      weight = @arbitrary_weights[name] -> put_style(acc, :font_weight, weight)
      name == "" or String.match?(name, ~r/^\d+$/) -> unknown(acc, class)
      true -> put_style(acc, :font_family, String.replace(name, "_", " "))
    end
  end

  # Tailwind's default box shadows as {x, y, blur, spread, color, inset}.
  @shadows %{
    "none" => [],
    "2xs" => [{0.0, 1.0, 0.0, 0.0, {:rgba, 13}, false}],
    "xs" => [{0.0, 1.0, 2.0, 0.0, {:rgba, 13}, false}],
    "sm" => [{0.0, 1.0, 2.0, 0.0, {:rgba, 13}, false}],
    "" => [{0.0, 1.0, 3.0, 0.0, {:rgba, 26}, false}, {0.0, 1.0, 2.0, -1.0, {:rgba, 26}, false}],
    "md" => [{0.0, 4.0, 6.0, -1.0, {:rgba, 26}, false}, {0.0, 2.0, 4.0, -2.0, {:rgba, 26}, false}],
    "lg" => [
      {0.0, 10.0, 15.0, -3.0, {:rgba, 26}, false},
      {0.0, 4.0, 6.0, -4.0, {:rgba, 26}, false}
    ],
    "xl" => [
      {0.0, 20.0, 25.0, -5.0, {:rgba, 26}, false},
      {0.0, 8.0, 10.0, -6.0, {:rgba, 26}, false}
    ],
    "2xl" => [{0.0, 25.0, 50.0, -12.0, {:rgba, 64}, false}],
    "inner" => [{0.0, 2.0, 4.0, 0.0, {:rgba, 13}, true}]
  }

  defp shadow(acc, name, class) do
    case Map.fetch(@shadows, name) do
      {:ok, layers} -> put_style(acc, :box_shadow, layers)
      :error -> unknown(acc, class)
    end
  end

  # `shadow-[0_1px_2px_#0003,inset_0_0_0_1px_rgba(0,0,0,0.1)]`: layers are comma separated
  # (outside parentheses), tokens underscore separated.
  # shortcut: colors must be the last token and contain no underscores, add if needed.
  defp arbitrary_shadow(acc, rest, class) do
    with [body, ""] <- String.split(rest, "]", parts: 2),
         layers when layers != [] <- split_layers(body),
         {:ok, parsed} <- parse_shadow_layers(layers) do
      put_style(acc, :box_shadow, parsed)
    else
      _invalid -> unknown(acc, class)
    end
  end

  defp split_layers(body), do: Regex.split(~r/,(?![^(]*\))/, body)

  defp parse_shadow_layers(layers) do
    parsed = Enum.map(layers, &parse_shadow_layer/1)
    if :error in parsed, do: :error, else: {:ok, Enum.map(parsed, &elem(&1, 1))}
  end

  defp parse_shadow_layer(layer) do
    {inset, tokens} =
      case String.split(layer, "_", trim: true) do
        ["inset" | tokens] -> {true, tokens}
        tokens -> {false, tokens}
      end

    with true <- length(tokens) in 3..5,
         {lengths, [color]} <- Enum.split(tokens, -1),
         {:ok, [x, y | rest]} <- shadow_lengths(lengths),
         [blur, spread] <- Enum.take(rest ++ [0.0, 0.0], 2),
         true <- blur >= 0.0,
         {:ok, color} <- shadow_color(color) do
      {:ok, {x, y, blur, spread, color, inset}}
    else
      _invalid -> :error
    end
  end

  defp shadow_lengths(tokens) do
    lengths = Enum.map(tokens, &shadow_length/1)
    if :error in lengths, do: :error, else: {:ok, lengths}
  end

  defp shadow_length(token) do
    with true <- Regex.match?(~r/^-?\d+(\.\d+)?(px)?$/, token),
         {number, _unit} <- Float.parse(token) do
      number
    else
      _invalid -> :error
    end
  end

  defp shadow_color("#" <> hex) when byte_size(hex) in [3, 4, 6, 8] do
    with {:ok, color} <- parse_hex_color(hex), do: {:ok, to_rgba(color)}
  end

  defp shadow_color(color) do
    with [_, channels] <- Regex.run(~r/^rgba?\((.*)\)$/, color),
         [r, g, b | alpha] <- channels |> String.split(",") |> Enum.map(&String.trim/1),
         [r, g, b] <- Enum.map([r, g, b], &Integer.parse/1),
         true <- Enum.all?([r, g, b], &match?({n, ""} when n in 0..255, &1)),
         {:ok, alpha} <- shadow_alpha(alpha) do
      {:ok,
       {:rgba,
        Bitwise.bsl(elem(r, 0), 24) + Bitwise.bsl(elem(g, 0), 16) + Bitwise.bsl(elem(b, 0), 8) +
          alpha}}
    else
      _invalid -> :error
    end
  end

  defp to_rgba({:rgba, _value} = color), do: color
  defp to_rgba({:rgb, value}), do: {:rgba, Bitwise.bsl(value, 8) + 255}

  defp shadow_alpha([]), do: {:ok, 255}

  defp shadow_alpha([alpha]) do
    {number, divisor} =
      case String.split_at(alpha, -1) do
        {percentage, "%"} -> {percentage, 100.0}
        _plain -> {alpha, 1.0}
      end

    case Float.parse(number) do
      {value, ""} when value >= 0 and value <= divisor -> {:ok, round(255 * value / divisor)}
      _invalid -> :error
    end
  end

  defp shadow_alpha(_alpha), do: :error

  defp normalize_class("relative", acc), do: put_style(acc, :position, :relative)
  defp normalize_class("absolute", acc), do: put_style(acc, :position, :absolute)
  defp normalize_class("flex-1", acc), do: put_style(acc, :flex, :one)
  defp normalize_class("flex-auto", acc), do: put_style(acc, :flex, :auto)
  defp normalize_class("flex-initial", acc), do: put_style(acc, :flex, :initial)
  defp normalize_class("flex-none", acc), do: put_style(acc, :flex, :none)
  defp normalize_class("flex", acc), do: put_style(acc, :display, :flex)
  defp normalize_class("block", acc), do: put_style(acc, :display, :block)
  defp normalize_class("grid", acc), do: put_style(acc, :display, :grid)
  defp normalize_class("hidden", acc), do: put_style(acc, :display, :none)
  defp normalize_class("flex-col", acc), do: put_style(acc, :flex_direction, :column)

  defp normalize_class("flex-col-reverse", acc),
    do: put_style(acc, :flex_direction, :column_reverse)

  defp normalize_class("flex-row", acc), do: put_style(acc, :flex_direction, :row)
  defp normalize_class("flex-row-reverse", acc), do: put_style(acc, :flex_direction, :row_reverse)
  defp normalize_class("flex-wrap", acc), do: put_style(acc, :flex_wrap, :wrap)
  defp normalize_class("flex-wrap-reverse", acc), do: put_style(acc, :flex_wrap, :wrap_reverse)
  defp normalize_class("flex-nowrap", acc), do: put_style(acc, :flex_wrap, :nowrap)
  defp normalize_class("basis-auto", acc), do: put_style(acc, :flex_basis, :auto)
  defp normalize_class("basis-" <> value, acc), do: length_value(acc, :flex_basis, value)
  defp normalize_class("grow", acc), do: put_style(acc, :flex_grow, 1.0)
  defp normalize_class("grow-0", acc), do: put_style(acc, :flex_grow, 0.0)
  defp normalize_class("shrink", acc), do: put_style(acc, :flex_shrink, 1.0)
  defp normalize_class("shrink-0", acc), do: put_style(acc, :flex_shrink, 0.0)
  defp normalize_class("items-center", acc), do: put_style(acc, :align_items, :center)
  defp normalize_class("items-start", acc), do: put_style(acc, :align_items, :start)
  defp normalize_class("items-end", acc), do: put_style(acc, :align_items, :end)
  defp normalize_class("items-baseline", acc), do: put_style(acc, :align_items, :baseline)
  defp normalize_class("items-stretch", acc), do: put_style(acc, :align_items, :stretch)
  defp normalize_class("justify-center", acc), do: put_style(acc, :justify_content, :center)
  defp normalize_class("justify-start", acc), do: put_style(acc, :justify_content, :start)
  defp normalize_class("justify-end", acc), do: put_style(acc, :justify_content, :end)
  defp normalize_class("justify-between", acc), do: put_style(acc, :justify_content, :between)
  defp normalize_class("justify-around", acc), do: put_style(acc, :justify_content, :around)
  defp normalize_class("justify-evenly", acc), do: put_style(acc, :justify_content, :evenly)
  defp normalize_class("overflow-hidden", acc), do: put_style(acc, :overflow, :hidden)
  defp normalize_class("whitespace-normal", acc), do: put_style(acc, :white_space, :normal)
  defp normalize_class("whitespace-nowrap", acc), do: put_style(acc, :white_space, :nowrap)
  defp normalize_class("text-ellipsis", acc), do: put_style(acc, :text_overflow, :ellipsis)
  defp normalize_class("text-left", acc), do: put_style(acc, :text_align, :left)
  defp normalize_class("text-center", acc), do: put_style(acc, :text_align, :center)
  defp normalize_class("text-right", acc), do: put_style(acc, :text_align, :right)
  defp normalize_class("italic", acc), do: put_style(acc, :font_style, :italic)
  defp normalize_class("not-italic", acc), do: put_style(acc, :font_style, :normal)
  defp normalize_class("underline", acc), do: put_style(acc, :underline, true)
  defp normalize_class("line-through", acc), do: put_style(acc, :line_through, true)

  defp normalize_class("no-underline", acc),
    do: update_in(acc.style, &Keyword.delete(&1, :underline))

  defp normalize_class("uppercase", acc), do: put_style(acc, :text_transform, :uppercase)
  defp normalize_class("lowercase", acc), do: put_style(acc, :text_transform, :lowercase)
  defp normalize_class("capitalize", acc), do: put_style(acc, :text_transform, :capitalize)
  defp normalize_class("normal-case", acc), do: put_style(acc, :text_transform, :none)
  defp normalize_class("truncate", acc), do: put_style(acc, :truncate, true)
  defp normalize_class("cursor-default", acc), do: put_style(acc, :cursor, :default)
  defp normalize_class("cursor-pointer", acc), do: put_style(acc, :cursor, :pointer)
  defp normalize_class("cursor-text", acc), do: put_style(acc, :cursor, :text)
  defp normalize_class("cursor-move", acc), do: put_style(acc, :cursor, :move)
  defp normalize_class("cursor-not-allowed", acc), do: put_style(acc, :cursor, :not_allowed)

  defp normalize_class("font-[" <> rest, acc) do
    case String.split(rest, "]", parts: 2) do
      [name, ""] -> font_family(acc, name, "font-[" <> rest)
      _ -> unknown(acc, "font-[" <> rest)
    end
  end

  defp normalize_class("font-thin", acc), do: put_style(acc, :font_weight, :thin)
  defp normalize_class("font-extralight", acc), do: put_style(acc, :font_weight, :extra_light)
  defp normalize_class("font-light", acc), do: put_style(acc, :font_weight, :light)
  defp normalize_class("font-normal", acc), do: put_style(acc, :font_weight, :normal)
  defp normalize_class("font-medium", acc), do: put_style(acc, :font_weight, :medium)
  defp normalize_class("font-semibold", acc), do: put_style(acc, :font_weight, :semibold)
  defp normalize_class("font-bold", acc), do: put_style(acc, :font_weight, :bold)
  defp normalize_class("font-extrabold", acc), do: put_style(acc, :font_weight, :extra_bold)
  defp normalize_class("font-black", acc), do: put_style(acc, :font_weight, :black)
  defp normalize_class("border", acc), do: put_style(acc, :border_width, {:px, 1.0})
  defp normalize_class("border-solid", acc), do: put_style(acc, :border_style, :solid)
  defp normalize_class("border-dashed", acc), do: put_style(acc, :border_style, :dashed)

  defp normalize_class("border-" <> rest, acc) do
    case border_side(rest) do
      {:ok, keys, width} -> Enum.reduce(keys, acc, &put_style(&2, &1, width))
      :error -> color(acc, :border_color, rest, "border-")
    end
  end

  defp normalize_class("rounded" <> suffix = class, acc) do
    radius =
      if suffix == "",
        do: {:ok, {:px, 4.0}},
        else: rounded_radius(String.trim_leading(suffix, "-"))

    case radius do
      {:ok, value} -> put_style(acc, :border_radius, value)
      :error -> unknown(acc, class)
    end
  end

  defp normalize_class("inset-auto", acc), do: put_style(acc, :inset, :auto)
  defp normalize_class("inset-x-auto", acc), do: put_style(acc, :inset_x, :auto)
  defp normalize_class("inset-y-auto", acc), do: put_style(acc, :inset_y, :auto)
  defp normalize_class("top-auto", acc), do: put_style(acc, :top, :auto)
  defp normalize_class("right-auto", acc), do: put_style(acc, :right, :auto)
  defp normalize_class("bottom-auto", acc), do: put_style(acc, :bottom, :auto)
  defp normalize_class("left-auto", acc), do: put_style(acc, :left, :auto)

  defp normalize_class("-inset-x-" <> value, acc),
    do: position_length(acc, :inset_x, "-" <> value)

  defp normalize_class("-inset-y-" <> value, acc),
    do: position_length(acc, :inset_y, "-" <> value)

  defp normalize_class("-inset-" <> value, acc), do: position_length(acc, :inset, "-" <> value)
  defp normalize_class("-top-" <> value, acc), do: position_length(acc, :top, "-" <> value)
  defp normalize_class("-right-" <> value, acc), do: position_length(acc, :right, "-" <> value)
  defp normalize_class("-bottom-" <> value, acc), do: position_length(acc, :bottom, "-" <> value)
  defp normalize_class("-left-" <> value, acc), do: position_length(acc, :left, "-" <> value)
  defp normalize_class("inset-x-" <> value, acc), do: position_length(acc, :inset_x, value)
  defp normalize_class("inset-y-" <> value, acc), do: position_length(acc, :inset_y, value)
  defp normalize_class("inset-" <> value, acc), do: position_length(acc, :inset, value)
  defp normalize_class("top-" <> value, acc), do: position_length(acc, :top, value)
  defp normalize_class("right-" <> value, acc), do: position_length(acc, :right, value)
  defp normalize_class("bottom-" <> value, acc), do: position_length(acc, :bottom, value)
  defp normalize_class("left-" <> value, acc), do: position_length(acc, :left, value)
  defp normalize_class("gap-" <> value, acc), do: spacing(acc, :gap, value)
  defp normalize_class("p-" <> value, acc), do: spacing(acc, :padding, value)
  defp normalize_class("px-" <> value, acc), do: spacing(acc, :padding_x, value)
  defp normalize_class("py-" <> value, acc), do: spacing(acc, :padding_y, value)
  defp normalize_class("pt-" <> value, acc), do: spacing(acc, :padding_top, value)
  defp normalize_class("pr-" <> value, acc), do: spacing(acc, :padding_right, value)
  defp normalize_class("pb-" <> value, acc), do: spacing(acc, :padding_bottom, value)
  defp normalize_class("pl-" <> value, acc), do: spacing(acc, :padding_left, value)
  defp normalize_class("m-" <> value, acc), do: spacing(acc, :margin, value)
  defp normalize_class("mx-" <> value, acc), do: spacing(acc, :margin_x, value)
  defp normalize_class("my-" <> value, acc), do: spacing(acc, :margin_y, value)
  defp normalize_class("mt-" <> value, acc), do: spacing(acc, :margin_top, value)
  defp normalize_class("mr-" <> value, acc), do: spacing(acc, :margin_right, value)
  defp normalize_class("mb-" <> value, acc), do: spacing(acc, :margin_bottom, value)
  defp normalize_class("ml-" <> value, acc), do: spacing(acc, :margin_left, value)
  defp normalize_class("w-" <> value, acc), do: length_value(acc, :width, value)
  defp normalize_class("h-" <> value, acc), do: length_value(acc, :height, value)
  defp normalize_class("min-w-" <> value, acc), do: length_value(acc, :min_width, value)
  defp normalize_class("max-w-" <> value, acc), do: length_value(acc, :max_width, value)
  defp normalize_class("min-h-" <> value, acc), do: length_value(acc, :min_height, value)
  defp normalize_class("max-h-" <> value, acc), do: length_value(acc, :max_height, value)

  defp normalize_class("size-" <> value, acc) do
    case parse_length(value) do
      {:ok, length} -> acc |> put_style(:width, length) |> put_style(:height, length)
      :error -> unknown(acc, "size-#{value}")
    end
  end

  defp normalize_class("active:bg-" <> color, acc),
    do: color(acc, :active_background, color, "active:bg-")

  defp normalize_class("active:text-" <> color, acc),
    do: color(acc, :active_color, color, "active:text-")

  defp normalize_class("active:border-" <> color, acc),
    do: color(acc, :active_border_color, color, "active:border-")

  defp normalize_class("active:opacity-" <> value, acc),
    do: opacity(value, acc, :active_opacity, "active:opacity-")

  defp normalize_class("hover:bg-" <> color, acc),
    do: color(acc, :hover_background, color, "hover:bg-")

  defp normalize_class("hover:text-" <> color, acc),
    do: color(acc, :hover_color, color, "hover:text-")

  defp normalize_class("hover:border-" <> color, acc),
    do: color(acc, :hover_border_color, color, "hover:border-")

  defp normalize_class("focus-within:bg-" <> color, acc),
    do: color(acc, :focus_within_background, color, "focus-within:bg-")

  defp normalize_class("focus-within:text-" <> color, acc),
    do: color(acc, :focus_within_color, color, "focus-within:text-")

  defp normalize_class("focus-within:border-" <> color, acc),
    do: color(acc, :focus_within_border_color, color, "focus-within:border-")

  defp normalize_class("focus-visible:bg-" <> color, acc),
    do: color(acc, :focus_visible_background, color, "focus-visible:bg-")

  defp normalize_class("focus-visible:text-" <> color, acc),
    do: color(acc, :focus_visible_color, color, "focus-visible:text-")

  defp normalize_class("focus-visible:border-" <> color, acc),
    do: color(acc, :focus_visible_border_color, color, "focus-visible:border-")

  defp normalize_class("focus-visible:opacity-" <> value, acc),
    do: opacity(value, acc, :focus_visible_opacity, "focus-visible:opacity-")

  defp normalize_class("focus:bg-" <> color, acc),
    do: color(acc, :focus_background, color, "focus:bg-")

  defp normalize_class("focus:text-" <> color, acc),
    do: color(acc, :focus_color, color, "focus:text-")

  defp normalize_class("focus:border-" <> color, acc),
    do: color(acc, :focus_border_color, color, "focus:border-")

  defp normalize_class("hover:opacity-" <> value, acc),
    do: opacity(value, acc, :hover_opacity, "hover:opacity-")

  defp normalize_class("focus-within:opacity-" <> value, acc),
    do: opacity(value, acc, :focus_within_opacity, "focus-within:opacity-")

  defp normalize_class("focus:opacity-" <> value, acc),
    do: opacity(value, acc, :focus_opacity, "focus:opacity-")

  defp normalize_class("shadow", acc), do: shadow(acc, "", "shadow")

  defp normalize_class("shadow-[" <> rest, acc),
    do: arbitrary_shadow(acc, rest, "shadow-[" <> rest)

  defp normalize_class("shadow-" <> name = class, acc), do: shadow(acc, name, class)
  defp normalize_class("bg-" <> color, acc), do: color(acc, :background, color, "bg-")
  defp normalize_class("text-" <> size_or_color, acc), do: text(size_or_color, acc)
  defp normalize_class("leading-" <> value, acc), do: line_height(value, acc)
  defp normalize_class("opacity-" <> value, acc), do: opacity(value, acc, :opacity, "opacity-")
  defp normalize_class(class, acc), do: unknown(acc, class)

  defp text(value, acc) do
    cond do
      Map.has_key?(@text_sizes, value) ->
        put_style(acc, :font_size, {:px, Map.fetch!(@text_sizes, value)})

      match?({:ok, _value}, parse_arbitrary_px(value)) ->
        {:ok, px} = parse_arbitrary_px(value)
        put_style(acc, :font_size, {:px, px})

      true ->
        color(acc, :color, value, "text-")
    end
  end

  defp line_height(value, acc) do
    case {Map.fetch(@line_heights, value), parse_arbitrary_px(value)} do
      {{:ok, px}, _arbitrary} -> put_style(acc, :line_height, {:px, px})
      {:error, {:ok, px}} -> put_style(acc, :line_height, {:px, px})
      {:error, :error} -> unknown(acc, "leading-#{value}")
    end
  end

  defp opacity("[" <> _rest = value, acc, key, prefix) do
    case parse_arbitrary_number(value) do
      {:ok, opacity} when opacity >= 0.0 and opacity <= 1.0 ->
        put_style(acc, key, opacity)

      _other ->
        unknown(acc, prefix <> value)
    end
  end

  defp opacity(value, acc, key, prefix) do
    case Integer.parse(value) do
      {opacity, ""} when opacity in 0..100 -> put_style(acc, key, opacity / 100)
      _other -> unknown(acc, prefix <> value)
    end
  end

  defp color(acc, key, value, prefix) do
    with {:ok, color_name, alpha} <- split_color_alpha(value),
         {:ok, color} <- fetch_color(color_name),
         {:ok, color} <- apply_color_alpha(color, alpha) do
      put_style(acc, key, color)
    else
      :error -> unknown(acc, prefix <> value)
    end
  end

  defp split_color_alpha(value) do
    case String.split(value, "/", parts: 2) do
      [color] -> {:ok, color, nil}
      [color, alpha] -> parse_color_alpha(color, alpha)
    end
  end

  defp parse_color_alpha(color, alpha) do
    case Integer.parse(alpha) do
      {percentage, ""} when percentage in 0..100 -> {:ok, color, percentage}
      _other -> :error
    end
  end

  defp fetch_color(value) do
    case GPUI.Tailwind.Palette.fetch(value) do
      {:ok, color} -> {:ok, color}
      :error -> parse_arbitrary_color(value)
    end
  end

  defp parse_arbitrary_color("[#" <> rest) do
    case String.split(rest, "]", parts: 2) do
      [hex, ""] when byte_size(hex) in [3, 4, 6, 8] -> parse_hex_color(hex)
      _other -> :error
    end
  end

  defp parse_arbitrary_color(_value), do: :error

  defp parse_hex_color(hex) do
    expanded =
      case String.graphemes(hex) do
        [r, g, b] -> r <> r <> g <> g <> b <> b
        [r, g, b, a] -> r <> r <> g <> g <> b <> b <> a <> a
        _long_form -> hex
      end

    case Integer.parse(expanded, 16) do
      {value, ""} when byte_size(expanded) == 6 -> {:ok, {:rgb, value}}
      {value, ""} when byte_size(expanded) == 8 -> {:ok, {:rgba, value}}
      _other -> :error
    end
  end

  defp apply_color_alpha(color, nil), do: {:ok, color}

  defp apply_color_alpha({:rgb, rgb}, percentage),
    do: {:ok, {:rgba, Bitwise.bsl(rgb, 8) + alpha_channel(percentage)}}

  defp apply_color_alpha({:rgba, rgba}, percentage) do
    alpha = Bitwise.band(rgba, 0xFF)
    adjusted = round(alpha * percentage / 100)
    {:ok, {:rgba, Bitwise.band(rgba, 0xFFFFFF00) + adjusted}}
  end

  defp alpha_channel(percentage), do: round(255 * percentage / 100)

  # `border-t`, `border-x-2` and `border-b-[1.5px]` set per-side widths; anything else is a colour.
  defp border_side(rest) do
    {side, width} =
      case String.split(rest, "-", parts: 2) do
        [side] -> {side, "1"}
        [side, width] -> {side, width}
      end

    sides = %{
      "t" => [:border_top_width],
      "b" => [:border_bottom_width],
      "l" => [:border_left_width],
      "r" => [:border_right_width],
      "x" => [:border_left_width, :border_right_width],
      "y" => [:border_top_width, :border_bottom_width]
    }

    with {:ok, keys} <- Map.fetch(sides, side),
         {:ok, px} <- border_width(width) do
      {:ok, keys, {:px, px}}
    end
  end

  defp border_width(width) when width in ["0", "1", "2", "4", "8"],
    do: {:ok, :erlang.float(String.to_integer(width))}

  defp border_width(width), do: parse_arbitrary_px(width)

  defp spacing(acc, key, value) do
    case parse_spacing(value) do
      {:ok, px} -> put_style(acc, key, {:px, px})
      :error -> unknown(acc, class_name(key, value))
    end
  end

  defp position_length(acc, key, "-" <> value) do
    case parse_position_length(value) do
      {:ok, {:px, px}} -> put_style(acc, key, {:px, -px})
      {:ok, {:fraction, fraction}} -> put_style(acc, key, {:fraction, -fraction})
      _other -> unknown(acc, class_name(key, "-#{value}"))
    end
  end

  defp position_length(acc, key, value) do
    case parse_position_length(value) do
      {:ok, length} -> put_style(acc, key, length)
      :error -> unknown(acc, class_name(key, value))
    end
  end

  defp parse_position_length("full"), do: {:ok, :full}

  defp parse_position_length("[" <> _rest = value), do: parse_arbitrary_length(value)

  defp parse_position_length(value), do: parse_length(value)

  defp length_value(acc, key, value) do
    case parse_length(value) do
      {:ok, length} -> put_style(acc, key, length)
      :error -> unknown(acc, class_name(key, value))
    end
  end

  defp class_name(key, value) do
    prefix =
      %{
        inset: "inset",
        inset_x: "inset-x",
        inset_y: "inset-y",
        top: "top",
        right: "right",
        bottom: "bottom",
        left: "left",
        gap: "gap",
        padding: "p",
        padding_x: "px",
        padding_y: "py",
        padding_top: "pt",
        padding_right: "pr",
        padding_bottom: "pb",
        padding_left: "pl",
        margin: "m",
        margin_x: "mx",
        margin_y: "my",
        margin_top: "mt",
        margin_right: "mr",
        margin_bottom: "mb",
        margin_left: "ml",
        flex_basis: "basis",
        width: "w",
        height: "h",
        min_width: "min-w",
        max_width: "max-w",
        min_height: "min-h",
        max_height: "max-h"
      }
      |> Map.fetch!(key)

    "#{prefix}-#{value}"
  end

  defp parse_length("full"), do: {:ok, :full}

  defp parse_length("[" <> _rest = value), do: parse_arbitrary_length(value)

  defp parse_length(value) do
    case parse_fraction(value) do
      {:ok, fraction} -> {:ok, {:fraction, fraction}}
      :error -> parse_spacing_length(value)
    end
  end

  defp parse_arbitrary_length(value) do
    case parse_arbitrary(value) do
      {:ok, {:px, number}} -> {:ok, {:px, number}}
      {:ok, {:percent, percentage}} -> {:ok, {:fraction, percentage / 100}}
      :error -> :error
    end
  end

  defp parse_spacing_length(value) do
    case parse_spacing(value) do
      {:ok, px} -> {:ok, {:px, px}}
      :error -> :error
    end
  end

  defp parse_spacing(value) do
    case Float.parse(value) do
      {number, ""} when number >= 0.0 -> {:ok, number * @spacing_unit}
      _other -> parse_arbitrary_px(value)
    end
  end

  defp parse_fraction(value) do
    case String.split(value, "/", parts: 2) do
      [numerator, denominator] ->
        with {numerator, ""} <- Float.parse(numerator),
             {denominator, ""} when denominator > 0.0 <- Float.parse(denominator),
             fraction when fraction >= 0.0 and fraction <= 1.0 <- numerator / denominator do
          {:ok, fraction}
        else
          _other -> :error
        end

      _other ->
        :error
    end
  end

  defp parse_arbitrary_px(value) do
    case parse_arbitrary(value) do
      {:ok, {:px, px}} -> {:ok, px}
      _other -> :error
    end
  end

  defp parse_arbitrary_number("[" <> rest) do
    with value when value != rest <- String.trim_trailing(rest, "]"),
         {number, ""} <- Float.parse(value) do
      {:ok, number}
    else
      _other -> :error
    end
  end

  defp parse_arbitrary_number(_value), do: :error

  defp parse_arbitrary("[" <> rest) do
    case String.trim_trailing(rest, "]") do
      ^rest ->
        :error

      value ->
        cond do
          String.ends_with?(value, "px") -> parse_unit(value, "px", :px)
          String.ends_with?(value, "%") -> parse_unit(value, "%", :percent)
          true -> :error
        end
    end
  end

  defp parse_arbitrary(_value), do: :error

  defp parse_unit(value, suffix, unit) do
    value = String.trim_trailing(value, suffix)

    case Float.parse(value) do
      {number, ""} -> {:ok, {unit, number}}
      _other -> :error
    end
  end

  defp rounded_radius("[" <> _rest = value) do
    case parse_arbitrary_px(value) do
      {:ok, px} -> {:ok, {:px, px}}
      :error -> :error
    end
  end

  defp rounded_radius("none"), do: {:ok, {:px, 0.0}}
  defp rounded_radius("sm"), do: {:ok, {:px, 2.0}}
  defp rounded_radius("md"), do: {:ok, {:px, 6.0}}
  defp rounded_radius("lg"), do: {:ok, {:px, 8.0}}
  defp rounded_radius("full"), do: {:ok, :full}
  defp rounded_radius(value) when value in ["", "DEFAULT"], do: {:ok, {:px, 4.0}}
  defp rounded_radius(_value), do: :error

  defp put_style(acc, key, value),
    do: update_in(acc.style, &[{key, value} | Keyword.delete(&1, key)])

  defp unknown(acc, class), do: update_in(acc.unknown, &[class | &1])
end
