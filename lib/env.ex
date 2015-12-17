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
  def env_map(code) do
    import Kernel, except: [defmodule: 2]
    import RPlugin.Env.FakeKernel
    try do
      Code.eval_string(code,[],%{__ENV__|module: Elixir,function: nil,line: 1})
    catch _,_->:ok end
    get_envs([]) |> Enum.sort_by(fn {{starts,ends},env}->ends-starts end)
  end

  def env_for_line(line,envmap) do
    Enum.find_value(envmap, fn 
      {{starts,ends},env} when line > starts and line <= ends-> env
      _-> nil
    end)
  end

  def get_envs(acc) do
    receive do env->get_envs([env|acc]) after 0->acc end
  end
end
