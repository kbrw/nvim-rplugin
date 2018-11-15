defmodule RPlugin.Doc.Cache do
  use GenServer
  def get_or(key,fun), do: GenServer.call(__MODULE__,{:get_or,key,fun})
  defmacro cached({{:.,_,modfun},_,args}=call) do quote do
    RPlugin.Doc.Cache.get_or({unquote(modfun),unquote(args)}, fn-> unquote(call) end)
  end end

  def start_link, do: GenServer.start_link(__MODULE__,[], name: __MODULE__)
  def init([]), do: {:ok,:ets.new(:doccache,[:set])}
  def handle_cast({:cache,key,res},tid) do
    :ets.insert(tid,{key,res})
    {:noreply,tid}
  end
  def handle_call({:get_or,key,fun},repto,tid) do
    case :ets.lookup(tid, key) do
      [{_,res}]->{:reply,res,tid}
      _ -> spawn fn-> 
        res = fun.()
        GenServer.cast(__MODULE__,{:cache,key,res})
        GenServer.reply(repto,res)
      end; {:noreply,tid}
    end
  end
end

defmodule RPlugin.Doc do
  import RPlugin.Doc.Cache, only: :macros

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
    case Code.Typespec.fetch_types(mod) do
      {:ok,types} when length(types) > 0->
        type_list = for {_,t}<-types do
          "- `#{Macro.to_string(Code.Typespec.type_to_quoted(t))}`"
        end |> Enum.join("\n")
        "## Types\n\n#{type_list}"
      _->nil
    end
  end
  def get({:funspecs,{mod,{f,a}}}) do
    case Code.Typespec.fetch_specs(mod) do
      {:ok,all_specs}->
        fun_specs = for {{f0,a0},specs}<-all_specs, {f0,a0}=={f,a}, spec<-specs, do: spec
        case fun_specs do
          []->nil
          specs->
            spec_lines = specs|>Enum.map(&Code.Typespec.spec_to_quoted(f,&1))
                              |>Enum.map(&"    #{Macro.to_string(&1)}")
                              |>Enum.join("\n")
            "## Specs\n\n#{spec_lines}"
        end
      _-> nil
    end
  end
  def get({:moduledoc,mod}) do
    case cached(Code.fetch_docs(mod)) do
      {:docs_v1, _, _, _, %{"en"=>doc}, _, _}->
        ["# Module #{inspect mod}",doc,get({:moduleinfo,{:functions,mod}}),get({:moduleinfo,{:macros,mod}}),get({:typespecs,mod})]
         |> Enum.reject(&is_nil/1) |> Enum.join("\n\n")
      _-> nil
    end
  end
  def get({:fundoc,{mod,fun}}) do
    case cached(Code.fetch_docs(mod)) do
      {:docs_v1, _, _, _, _, _, fundocs}->
        doc = for {{type,f,a},_,specs,fundoc,_}<-fundocs, f==fun do
          ["# #{type} #{specs |> Enum.map(&"#{inspect mod}.#{&1}") |> Enum.join(" ")}", 
            get({:funspecs,{mod,{f,a}}}), 
            case fundoc do %{"en"=>doc}-> "## Doc\n\n#{doc}"; _-> nil end ]
          |> Enum.reject(&is_nil/1) |> Enum.join("\n\n")
        end |> Enum.join("\n\n")
        if doc != "", do: doc
      _-> nil
    end
  end

  def get({:fun_preview,{mod,fun,arity}}) do
    case cached(Code.fetch_docs(mod)) do
      {:docs_v1, _, _, _, _, _, fundocs}->
        Enum.find_value(fundocs,fn
          {{_,f,a},_,_,%{"en"=>doc},_} when {f,a}=={fun,arity}-> md_first_line(doc)
          _->nil
        end)
      _-> nil
    end
  end
  def get({:mod_preview,mod}) do
    case cached(Code.fetch_docs(mod)) do
      {:docs_v1, _, _, _, %{"en"=>doc}, _, _}-> md_first_line(doc)
      _-> nil
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
