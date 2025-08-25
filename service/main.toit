// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

import encoding.tison
import system.assets
import max31865.provider
import max31865 show Driver

install-from-args_ args/List:
  if args.size != 3 and args.size != 4:
    throw "Usage: main <clock> <miso> <mosi> [<cs>]"
  clock := int.parse args[0]
  miso := int.parse args[1]
  mosi := int.parse args[2]
  cs/int? := (args.size == 4) ? (int.parse args[3]) : null
  provider.install --clock=clock --miso=miso --mosi=mosi --cs=cs

install-from-assets_ configuration/Map:
  clock := configuration.get "clock"
  if not clock: throw "No 'clock' found in assets."
  if clock is not int: throw "Clock must be an integer."
  miso := configuration.get "miso"
  if not miso: throw "No 'miso' found in assets."
  if miso is not int: throw "Miso must be an integer."
  mosi := configuration.get "mosi"
  if not mosi: throw "No 'mosi' found in assets."
  if mosi is not int: throw "Mosi must be an integer."
  cs := configuration.get "cs"
  if cs and cs is not int: throw "Cs must be an integer."
  provider.install --clock=clock --miso=miso --mosi=mosi --cs=cs

main args:
  // Arguments take priority over assets.
  if args.size != 0:
    install-from-args_ args
    return

  decoded := assets.decode
  ["configuration", "artemis.defines"].do: | key/string |
    configuration := decoded.get key
    if configuration:
      install-from-assets_ configuration
      return

  throw "No configuration found."
