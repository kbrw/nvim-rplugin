defmodule RPlugin.Mix do
  require Logger
  def mix_load("/"<>path) do
    mix_dir = path |> Path.split |> Enum.reduce([""],&["#{hd(&2)}/#{&1}"|&2])
                   |> Enum.reverse |> Enum.find(&File.exists?("#{&1}/mix.exs"))
    if mix_dir do
      Mix.start #ensure mix is started
      old_proj=Mix.Project.pop
      Code.load_file(mix_dir<>"/mix.exs")
      if old_proj do
        Logger.info("Replace project #{old_proj.config[:app]} by #{Mix.Project.config[:app]}")
      else
        Logger.info("Load project #{Mix.Project.config[:app]}")
      end
      if File.exists?(mix_dir<>"/config/config.exs"), do:
        Mix.Task.run("loadconfig", [mix_dir<>"/config/config.exs"])
      :file.set_cwd('#{mix_dir}') # if your application read files
      for p<-Path.wildcard("#{mix_dir}/_build/#{Mix.env}/lib/*/ebin"), do: :code.add_pathz('#{p}')
      for f<-Path.wildcard("#{mix_dir}/_build/#{Mix.env}/lib/*/ebin/*.app"),{:ok,[{:application,_,app}]}=:file.consult(to_char_list f),mod<-app[:modules] do
        Code.ensure_loaded(mod)
      end
    else
      Logger.info("Cannot find any mix project in parent dirs")
    end
  end

end
