# NvimRplugin

![autocomplete](autocomplete.gif)
thanks @archSeer for the gif !

# Features

- Load nearest mix project in current file path with `:MixLoad`
- Start the current mix project application inside your vim: `:MixStart`
- Add a complete function "ElixirComplete": iex completion and doc into vim
- Interpret the currently selected Elixir Code with `:ElixirExec`
- If no line selected, then the whole file is interpreted, useful to dynamically reload current file modules when the app runs with `:MixStart`
- Bindings are kept along interpretations
- You can reset binding using the bang: `:ElixirExec!`
- Add a function `ExdocGetBody` to get documentation under cursor

# Installation

Install neovim elixir host (see https://github.com/awetzel/neovim-elixir)
then compile your plugin as an archive and put the archive in the
`rplugin/elixir` directory of your neovim configuration.

```bash
mix archive.build
cp nvim_rplugin-0.0.1.ez ~/.config/nvim/rplugin/elixir/
```

# Configuration

Two possible configurations for the completion function:

- `g:elixir_maxmenu` is an integer giving the max length of the function doc
  preview in omni completion, default to 70
- `g:elixir_docpreview` is a boolean (int 0 or 1) to choose if you
  want the completion function to open doc in preview window or not,
  default to 0.
