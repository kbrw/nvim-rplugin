defmodule RPlugin.Env.FakeKernel do
  defmacro defmodule(name,do: block) do
    {_,lastline} = Macro.prewalk(block,nil,fn {_,[line: line],_}=e,acc->{e,max(acc || 0,line)}; e,acc->{e,acc} end)
    quote do
      Kernel.defmodule unquote(name) do 
        unquote(block) 
        send(unquote(self),{{__ENV__.line,unquote(lastline) || __ENV__.line},__ENV__})
      end
    end
  end
end

defmodule RPlugin.Env do
  require Logger
  def env_map(code,cur_file) do
    import Kernel, except: [defmodule: 2]
    import RPlugin.Env.FakeKernel
    res = try do
      Code.eval_string(code,[],%{__ENV__|module: Elixir,function: nil, file: cur_file, line: 1}); :ok
    catch
      :error,%{description: desc, line: line}-> {:error,desc,line}
      type,error-> {:error,inspect({type,error}),
                      Enum.find_value(System.stacktrace,fn {_,_,_,metas}->metas[:line] end)}
    end
    if match?({:ok,1},NVim.vim_get_var("elixir_showerror")) do
      NVim.vim_command("for m in getmatches() | call matchdelete(m.id) | endfor")
      case res do
        :ok-> :ok
        {:error,desc,nil}-> Logger.error(desc)
        {:error,desc,line}->
          Logger.warn("#{desc} (L#{line})")
          NVim.vim_call_function("matchaddpos",["SpellBad",[[line,1,2]],999])
      end
    end
    get_envs([]) |> Enum.sort_by(fn {{starts,ends},env}->ends-starts end)
  end

  def env_for_line(line,envmap) do
    Enum.find_value(envmap, fn 
      {{starts,ends},env} when line > starts and line <= ends-> env
      _-> nil
    end)
  end

  def get_envs(acc) do
    receive do {{_,_},%{}}=env->get_envs([env|acc]) after 0->acc end
  end
end
