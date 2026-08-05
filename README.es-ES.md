

# neotest-gtest
![CI status](https://github.com/alfaix/neotest-gtest/actions/workflows/workflow.yaml/badge.svg?event=push)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Este es un adaptador de [neotest] para [Google Test][google-test], una popular biblioteca de pruebas de C++. Permite interactuar fácilmente con las pruebas desde tu Neovim.
Debería funcionar bien desde el primer momento para la mayoría de los casos, aunque algunas características (ver más abajo) aún no están soportadas.

## Requisitos
* Neovim 0.9.1+, 0.10.x o nightly.
* [Google Test][google-test] 1.10+
* [neotest] (la última versión, incluyendo nvim-nio y plenary.nvim)
* [nvim-treesitter] (la última versión, con el analizador de CPP instalado mediante `TSInstall cpp`)
* [nvim-dap] (la última versión, _opcional_, requerido para depuración)

## Características

El complemento proporciona soporte completo para todas las funciones de neotest:

- ejecutar pruebas dentro de NeoVim
- ver salidas con buen formato
- depurar pruebas
- todas las demás ventajas de neotest

Hay dos características principales que aún no están soportadas:

- `TEST_P` (pruebas parametrizadas)
- Integración con herramientas de compilación para recompilar: por ahora, debes hacerlo manualmente (o con otro complemento)

¡Las contribuciones son bienvenidas! :)

## Instalación

Usa tu administrador de paquetes favorito. No olvides instalar [neotest] en sí, el cual también tiene un par de dependencias. El complemento también depende de `plenary.nvim`, es probable que lo hagan tus otros complementos también.

Para la **depuración**, también necesitas [nvim-dap] y un adaptador de depuración ([codelldb] es recomendado), puedes instalarlo manualmente o con [mason.nvim].
Para configurarlo, consulta la [wiki de nvim-dap][nvim-dap-wiki].

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
-- best to add to dependencies of `neotest`:
{
    "nvim-neotest/neotest",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "alfaix/neotest-gtest"
        -- your other adapters here
    }
}
```

## Uso

Simplemente agrega `neotest-gtest` al campo `adapters` de la configuración de neotest:

```lua
require("neotest").setup({
  adapters = {
    require("neotest-gtest").setup({})
  }
})
```

**Antes de ejecutar las pruebas**, necesitas asignarlas a ejecutables. Para ello, navega a la ventana de resumen de neotest (`neotest.summary.open()`), marca las pruebas que deseas ejecutar (`m` por defecto) y ejecuta `:ConfigureGtest` en esa misma ventana. Te pedirá ingresar la ruta al ejecutable. Puedes configurar la ruta del ejecutable solo para el directorio padre, no es necesario configurarla para cada prueba por separado. Esta configuración se guarda en disco.

Una vez hecho esto, usa `neotest` de la manera habitual: consulta su [documentación](https://github.com/nvim-neotest/neotest#usage).
No necesitas llamar a ninguna función de `neotest-gtest` para un uso normal.

## Configuración

`neotest-gtest` viene con los siguientes valores predeterminados:

```lua
local utils = require("neotest-gtest.utils")
local lib = require("neotest.lib")

require("neotest-gtest").setup({
  -- fun(string) -> string: toma una ruta de archivo como cadena y devuelve su directorio raíz del proyecto
  -- neotest.lib.files.match_root_pattern() es una fábrica conveniente para estas funciones:
  -- devuelve una función que retorna verdadero si el directorio contiene alguna entrada con nombres coincidentes
  root = lib.files.match_root_pattern(
    "compile_commands.json",
    "compile_flags.txt",
    "WORKSPACE",
    ".clangd",
    "init.lua",
    "init.vim",
    "build",
    ".git"
  ),
  -- ¿qué adaptador de depuración usar? dap.adapters.<este debug_adapter> debe estar definido.
  debug_adapter = "codelldb",
  -- fun(string) -> bool: toma una ruta de archivo como cadena y devuelve verdadero si contiene pruebas
  is_test_file = function(file)
    -- por defecto, devuelve verdadero si el nombre base del archivo comienza con test_ o termina con _test
    -- la extensión debe ser cpp/cppm/cc/cxx/c++
  end,
  -- Cuántos resultados de pruebas antiguos conservar en disco (almacenados en stdpath('data')/neotest-gtest/runs)
  history_size = 3,
  -- Para evitar que proyectos grandes congelen tu computadora, hay cierta regulación
  -- para -- analizar archivos de pruebas. Disminuye si tu análisis es lento y tienes una PC potente.
  parsing_throttle_ms = 10,
  -- asigna configure a una tecla de modo normal que ejecutará :ConfigureGtest (sugerencia:
  -- "C", nil por defecto)
  mappings = { configure = nil },
  summary_view = {
    -- ¿Cuánto de largo debe ser el encabezado en el resumen corto de pruebas?
    -- ________TestNamespace.TestName___________ <- este es el encabezado
    header_length = 80,
    -- Los colores de tu terminal, si los predeterminados no funcionan.
    shell_palette = {
      passed = "\27[32m",
      skipped = "\27[33m",
      failed = "\27[31m",
      stop = "\27[0m",
      bold = "\27[1m",
    },
  },
  -- ¿Qué argumentos adicionales se deben enviar SIEMPRE a google test?
  -- si deseas enviarlos para una sola invocación dada,
  -- envíalos a `neotest.run({extra_args = ...})`
  -- consulta :h neotest.RunArgs para más detalles
  extra_args = {},
  -- consulta :h neotest.Config.discovery. Es mejor mantenerlo así y configurar
  -- la configuración por proyecto en neotest en su lugar.
  filter_dir = function(name, rel_path, root)
    -- consulta :h neotest.Config.discovery para los valores predeterminados
  end,
})
```

## Contribuciones

Todas las contribuciones son bienvenidas. Si deseas contribuir pero no estás seguro de cómo comenzar, abre un issue (problema) y haré lo posible por ayudarte.

Si te sientes lo suficientemente seguro para escribir un PR (pull request) por tu cuenta, asegúrate de incluir pruebas. El complemento está bastante probado; puedes ejecutar `make` para correr las pruebas. La suite de pruebas de integración requiere un compilador C++11 funcional y descargará googletest como un submódulo.

## Licencia

MIT, ver [LICENSE](https://github.com/alfaix/neotest-gtest/blob/main/LICENSE)

[nvim-treesitter]: https://github.com/nvim-treesitter/nvim-treesitter
[neotest]: https://github.com/nvim-neotest/neotest
[google-test]: https://github.com/google/googletest
[nvim-dap]: https://github.com/mfussenegger/nvim-dap
[codelldb]: https://github.com/vadimcn/codelldb
[mason.nvim]: https://github.com/williamboman/mason.nvim
[nvim-dap-wiki]: https://github.com/mfussenegger/nvim-dap/wiki/C-C---Rust-(via--codelldb)
