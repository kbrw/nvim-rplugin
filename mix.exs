defmodule NvimRplugin.Mixfile do
  use Mix.Project

  def project do
    [app: :nvim_rplugin,
     version: "0.0.1",
     elixir: "~> 1.1",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  def application do
    [applications: []]
  end

  defp deps do
    [{:neovim, "~> 0.1", github: "awetzel/neovim-elixir"}]
  end
end
