defmodule RPlugin.Doc do
  def get({:q_doc,env,query}) do
    case String.split(query,".") do
      [<<c>><>_]=q when c in ?a..?z->
        q = :"#{q}"
        case for({mod,funs}<-env.functions, {fun,_}<-funs, fun == q, do: {mod,fun}) do
          []->
            case for({mod,funs}<-env.macros, {fun,_}<-funs, fun == q, do: {mod,fun}) do
              []->get({:fundoc,{env.module,q}})
              [{mod,fun}|_]->get({:fundoc,{mod,fun}})
            end
          [{mod,fun}|_]->get({:fundoc,{mod,fun}})
        end
      [":"<>erlmod]->get({:erldoc,erlmod})
      [":"<>erlmod,erlfun]->get({:erldoc,erlmod,erlfun})
      parts->
        if Enum.all?(parts, &match?(<<c>><>_ when c in ?A..?Z,&1)) do
          mod = resolve_alias(parts,env)
          get(if match?("Elixir."<>_,"#{mod}"), 
                    do: {:moduledoc,mod}, else: {:erldoc,mod})
        else
          mod = resolve_alias(Enum.slice(parts,0..-2),env)
          get(if match?("Elixir."<>_,"#{mod}"), 
                    do: {:fundoc,{mod, :"#{List.last parts}"}}, else: {:erldoc,mod,List.last(parts)})
        end
    end
  end

  def get({:q_fun_preview,env,{mod,fun,arity}}) do
    mod = resolve_alias([String.rstrip(mod,?.)],env)
    get({:fun_preview,{mod,:"#{fun}",String.to_integer(arity)}})
  end
  def get({:q_mod_preview,env,mod}) do
    get({:mod_preview,resolve_alias([mod],env)})
  end

  def get({:erldoc,erlmod}) do
    case to_string(:os.cmd('erl -man #{erlmod} | col -b')) do
      "No manual entry"<>_-> nil
      doc-> "erlmod/#{doc}"
    end
  end
  def get({:erldoc,erlmod,erlfun}) do
    case to_string(:os.cmd('erl -man #{erlmod} | col -b')) do
      "No manual entry"<>_-> nil
      doc-> "erlfun/#{erlfun}/#{doc}"
    end
  end
  def get({:moduleinfo,{type,mod}}) when type in [:functions,:macros] do
    case mod.__info__(type) do
      []->nil
      funs->
        fun_list = for {name,arity}<-funs do
          "- `#{inspect mod}.#{name}/#{arity}`"
        end |> Enum.join("\n")
        "## #{type |> to_string |> String.capitalize}\n\n#{fun_list}"
    end
  end
  def get({:typespecs,mod}) do
    case Kernel.Typespec.beam_types(mod) do
      []->nil
      types->
        type_list = for {_,t}<-types do
          "- `#{Macro.to_string(Kernel.Typespec.type_to_ast(t))}`"
        end |> Enum.join("\n")
        "## Types\n\n#{type_list}"
    end
  end
  def get({:funspecs,{mod,{f,a}}}) do
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
  def get({:moduledoc,mod}) do
    if moddoc=Code.get_docs(mod,:moduledoc) do
      ["# Module #{inspect mod}",elem(moddoc,1),get({:moduleinfo,{:functions,mod}}),get({:moduleinfo,{:macros,mod}}),get({:typespecs,mod})]
      |> Enum.reject(&is_nil/1) |> Enum.join("\n\n")
    end
  end
  def get({:fundoc,{mod,fun}}) do
    if fundocs=Code.get_docs(mod, :docs) do
      doc = for {{f,a},_,type,spec,doc}<-fundocs, f==fun do
        ["# #{type} `#{inspect mod}.#{Macro.to_string({fun,[],spec})}`", get({:funspecs,{mod,{f,a}}}), if(doc, do: "## Doc\n\n#{doc}")]
        |> Enum.reject(&is_nil/1) |> Enum.join("\n\n")
      end |> Enum.join("\n\n")
      if doc == "", do: nil, else: doc
    end
  end


  def get({:fun_preview,{mod,fun,arity}}) do
    if fundocs=Code.get_docs(mod,:docs) do
      Enum.find_value(fundocs,fn
        {{f,a},_,_,_,doc} when {f,a}=={fun,arity} and doc != nil-> md_first_line(doc)
        _->nil
      end)
    end
  end
  def get({:mod_preview,mod}) do
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

  defp resolve_alias(parts,env) do
    lambda_alias = Module.concat(parts)
    env.aliases[lambda_alias] || lambda_alias
  end
end
