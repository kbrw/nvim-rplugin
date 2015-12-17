defmodule RPlugin.Doc do
  def get(query) when is_binary(query), do: get(String.split(query,"."))
  def get([<<c>><>_]=q) when c in ?a..?z, do: get(["Kernel"|q])
  def get([":"<>erlmod|_rest]), do: get(:erldoc,erlmod)
  def get(query) when is_list(query) do
    if Enum.all?(query, &match?(<<c>><>_ when c in ?A..?Z,&1)) do
      get(:moduledoc,Module.concat(query))
    else
      get(:fundoc,{(query|>Enum.slice(0..-2)|>Module.concat), :"#{List.last query}"})
    end
  end

  def get(:erldoc,erlmod) do
    :os.cmd('erl -man #{erlmod} | col -b') |> to_string
  end
  def get(:moduleinfo,{type,mod}) when type in [:functions,:macros] do
    case mod.__info__(type) do
      []->nil
      funs->
        fun_list = for {name,arity}<-funs do
          "- `#{inspect mod}.#{name}/#{arity}`"
        end |> Enum.join("\n")
        "## #{type |> to_string |> String.capitalize}\n\n#{fun_list}"
    end
  end
  def get(:typespecs,mod) do
    case Kernel.Typespec.beam_types(mod) do
      []->nil
      types->
        type_list = for {_,t}<-types do
          "- `#{Macro.to_string(Kernel.Typespec.type_to_ast(t))}`"
        end |> Enum.join("\n")
        "## Types\n\n#{type_list}"
    end
  end
  def get(:funspecs,{mod,{f,a}}) do
    all_specs = Kernel.Typespec.beam_specs(mod)
    fun_specs = for {{f0,a0},specs}<-all_specs, {f0,a0}=={f,a}, spec<-specs, do: spec
    case fun_specs do
      []->nil
      specs->
        spec_lines = specs|>Enum.map(&Kernel.Typespec.spec_to_ast(f,&1))
                          |>Enum.map(&"    #{Macro.to_string(&1)}")
                          |>Enum.join("\n")
        "## Specs\n\n#{spec_lines}"
    end
  end
  def get(:moduledoc,mod) do
    if moddoc=Code.get_docs(mod,:moduledoc) do
      ["# Module #{inspect mod}",elem(moddoc,1),get(:moduleinfo,{:functions,mod}),get(:moduleinfo,{:macros,mod}),get(:typespecs,mod)]
      |> Enum.reject(&is_nil/1) |> Enum.join("\n\n")
    end
  end
  def get(:fundoc,{mod,fun}) do
    if fundocs=Code.get_docs(mod, :docs) do
      doc = for {{f,a},_,_,spec,doc}<-fundocs, f==fun do
        ["# `#{inspect mod}.#{Macro.to_string({fun,[],spec})}`", get(:funspecs,{mod,{f,a}}), if(doc, do: "## Doc\n\n#{doc}")]
        |> Enum.reject(&is_nil/1) |> Enum.join("\n\n")
      end |> Enum.join("\n\n")
      if doc == "", do: nil, else: doc
    end
  end

  def get(:fun_preview,{mod,fun,arity}) when is_binary(mod) do
    mod = Module.concat([String.rstrip(mod,?.)])
    get(:fun_preview,{mod,:"#{fun}",String.to_integer(arity)})
  end
  def get(:mod_preview,mod) when is_binary(mod), do:
   get(:mod_preview,Module.concat([mod]))

  def get(:fun_preview,{mod,fun,arity}) do
    if fundocs=Code.get_docs(mod,:docs) do
      Enum.find_value(fundocs,fn
        {{f,a},_,_,_,doc} when {f,a}=={fun,arity} and doc != nil-> md_first_line(doc)
        _->nil
      end)
    end
  end
  def get(:mod_preview,mod) do
    if moddoc=Code.get_docs(mod,:moduledoc) do
      if doc=elem(moddoc,1), do: md_first_line(doc)
    end
  end

  defp md_first_line(markdown) do
    markdown
    |> String.split("\n\n",parts: 2)
    |> hd
    |> String.replace("\n"," ")
  end
end
