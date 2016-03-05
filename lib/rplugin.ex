defmodule RPlugin do
  use NVim.Plugin
  require Logger
  alias RPlugin.Doc

  defmodule Sup do
    def start_link, do: Supervisor.start_link([
      worker(RPlugin,[%{}]),
      worker(RPlugin.Doc.Cache,[])
    ], strategy: :one_for_one)
  end
  def child_spec, do: supervisor(Sup,[])

  defp format_bindings(bindings) do
    bindings |> Enum.map(fn {k,v}->"#{k} = #{inspect(v,pretty: true, limit: :infinity)}" end) |> Enum.join("\n")
  end

  # - `current_bindings` is the state of bindings of ElixirExec command
  # - `file_envs` is the map nb_line->envs used to contextualize doc and completion
  # - `build_pid` current async build process to avoids concurrent file builds
  def init(_) do
    Process.flag(:trap_exit, true)
    state = %{current_bindings: [], file_envs: HashDict.new, build_pid: nil}
    {:ok,spawn_build(state, fn-> RPlugin.Mix.mix_load(System.cwd) end)}
  end

  def handle_cast({:new_envs,cur_file,envs},state), do:
    {:noreply,%{state|file_envs: Dict.put(state.file_envs,cur_file,envs)}}

  # do not spawn anything if a build pid is already set, else spawn and set it
  defp spawn_build(%{build_pid: nil}=state,fun), do:
    %{state| build_pid: spawn_link(fun)}
  defp spawn_build(%{build_pid: pid}=state,_) when is_pid(pid), do:
    state
  # when the build process ends (bad or normal), free the state to allow later build
  def handle_info({:EXIT,pid,_}, %{build_pid: pid}=state), do:
    {:noreply, %{state| build_pid: nil}}

  defcommand mix_start(app,_), async: true do
    Application.ensure_all_started(app && :"#{app}" || Mix.Project.config[:app])
  end

  defcommand mix_stop(app,_), async: true do
    Application.stop(app && :"#{app}" || Mix.Project.config[:app])
  end


  defcommand mix_load(file_dir,state), eval: "expand('%:p:h')", async: true do
    {:ok,nil,spawn_build(state,fn-> RPlugin.Mix.mix_load(file_dir) end)}
  end

  defcommand elixir_quick_build(ends,cur_file,state), eval: "line('$')", eval: "expand('%:p:h')", async: true do
    {:ok,nil,spawn_build(state, fn->
      {:ok,buffer} = NVim.vim_get_current_buffer
      {:ok,text} = NVim.buffer_get_line_slice(buffer,0,ends-1,true,true)
      GenServer.cast __MODULE__, {:new_envs,cur_file,RPlugin.Env.env_map(Enum.join(text,"\n"),cur_file)}
    end)}
  end

  defcommand elixir_exec(bang,[starts,ends],cur_file,state), bang: true, range: :default_all, eval: "expand('%:p:h')" do
    env = RPlugin.Env.env_for_line(starts,Dict.get(state.file_envs,cur_file,[])) || __ENV__
    {:ok,buffer} = NVim.vim_get_current_buffer
    {:ok,text} = NVim.buffer_get_line_slice(buffer,starts-1,ends-1,true,true)
    tmp_dir = System.tmp_dir || "."
    current_bindings = if bang == 0, do: state.current_bindings, else: []
    random_name = :crypto.hash(:md5,:erlang.term_to_binary(:os.timestamp)) |> Base.encode16 |> String.slice(0..10)
    bindings = try do
      {res,bindings} = Code.eval_string(Enum.join(text,"\n"),current_bindings, env)
      File.write!("#{tmp_dir}/#{random_name}.ex","#{inspect(res,pretty: true, limit: :infinity)}\n\n#{format_bindings bindings}")
      bindings
    catch
      kind,err->
        format_err = Exception.format(kind,err,System.stacktrace)
        File.write! "#{tmp_dir}/#{random_name}.ex","#{format_err}\n\n#{format_bindings current_bindings}"
        current_bindings
    end
    NVim.vim_command("pedit! #{tmp_dir}/#{random_name}.ex")
    {:ok,nil,%{state| current_bindings: bindings}}
  end

  deffunc docex_get_body(_q,cursor,line,cur_file,numline,state), eval: "col('.')", eval: "getline('.')",
                                                eval: "expand('%:p:h')", eval: "line('.')" do
    env = RPlugin.Env.env_for_line(numline,Dict.get(state.file_envs,cur_file,[])) || __ENV__
    [start_query] = Regex.run(~r"[\w\.:]*$",String.slice(line,0..cursor-1))
    [end_query] = Regex.run(~r"^[\w!?]*",String.slice(line,cursor..-1))
    Doc.get({:q_doc,env,start_query <> end_query}) |> to_string
  end

  deffunc elixir_complete(mode,_,cursor,line,_,_,_,_,minlen,state) when mode in ["1",1], eval: "col('.')", eval: "getline('.')",
      eval: "get(g:,'elixir_docpreview',0)", eval: "get(g:,'elixir_maxmenu',70)", 
      eval: "expand('%:p:h')", eval: "line('.')", eval: "get(g:,'elixir_comp_minlen',0)" do
    cursor = cursor - 1 # because we are in insert mode
    [tomatch] = Regex.run(~r"[\w\.:]*$",String.slice(line,0..cursor-1))
    if String.length(tomatch) < minlen, do: -3, else: cursor - String.length(tomatch)
  end
  deffunc elixir_complete(_,base,_,_,preview?,maxmenu,cur_file,numline,minlen,state), eval: "col('.')", eval: "getline('.')",
      eval: "get(g:,'elixir_docpreview',0)", eval: "get(g:,'elixir_maxmenu',70)", 
      eval: "expand('%:p:h')", eval: "line('.')", eval: "get(g:,'elixir_comp_minlen',0)" do
    if env=RPlugin.Env.env_for_line(numline,Dict.get(state.file_envs,cur_file,[])), do:
      Application.put_env(:iex, :autocomplete_server, %{current_env: env})
    env = env || __ENV__
    case (base |> to_char_list |> Enum.reverse |> IEx.Autocomplete.expand) do
      {:no,_,_}-> [base] # no expand
      {:yes,comp,[]}->["#{base}#{comp}"] #simple expand, no choices
      {:yes,_,alts}-> # multiple choices
        Enum.map(alts,fn comp->
          {base,comp} = {String.replace(base,~r"[^.]*$",""), to_string(comp)}
          case Regex.run(~r"^(.*)/([0-9]+)$",comp) do # first see if these choices are module or function
            [_,function,arity]-> # it is a function completion
              replace = base<>function
              menu = Doc.get({:q_fun_preview,env,{base,function,arity}}) |> to_string |> String.slice(0..maxmenu)
              if(preview?==1 && (doc=Doc.get({:q_doc,env,replace})), do: [{"info",doc}], else: [])
              |> Enum.into(%{"word"=>replace, "abbr"=>comp, "menu"=>menu, "dup"=>1})
            nil-> # it is a module completion
              replace = case comp do
                <<c>><>_ when c in ?a..?z-> ":#{comp}" # erlang module comp
                _ -> base<>comp
              end
              menu = Doc.get({:q_mod_preview,env,replace}) |> to_string |> String.slice(0..maxmenu)
              if(preview?==1 && (doc=Doc.get({:q_doc,env,replace})), do: [{"info",doc}], else: [])
              |> Enum.into(%{"word"=>replace, "menu"=>menu})
          end
        end)
    end
  end
end
