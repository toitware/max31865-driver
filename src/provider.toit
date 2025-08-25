// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

import gpio
import spi
import sensors.providers

import .driver as max31865

NAME ::= "toit.io/max31865"
MAJOR ::= 1
MINOR ::= 0

class Sensor_ implements providers.TemperatureSensor-v1:
  clock_/gpio.Pin? := null
  miso_/gpio.Pin? := null
  mosi_/gpio.Pin? := null
  cs_/gpio.Pin? := null
  spi_/spi.Bus? := null
  device_/spi.Device? := null
  sensor_/max31865.Driver? := null

  constructor --clock/int --miso/int --mosi/int --cs/int?:
    is-exception := true
    try:
      clock_ = gpio.Pin clock
      miso_ = gpio.Pin miso
      mosi_ = gpio.Pin mosi
      cs_ = cs ? gpio.Pin cs : null
      spi_ = spi.Bus --clock=clock_ --miso=miso_ --mosi=mosi_
      device_ = spi_.device --cs=cs_ --frequency=max31865.MAX-BUS-SPEED
      sensor_ = max31865.Driver device_
      is-exception = false
    finally:
      if is-exception: close

  temperature-read -> float?:
    return sensor_.read-temperature

  close -> none:
    if sensor_:
      sensor_ = null
    if device_:
      device_.close
      device_ = null
    if spi_:
      spi_.close
      spi_ = null
    if cs_:
      cs_.close
      cs_ = null
    if mosi_:
      mosi_.close
      mosi_ = null
    if miso_:
      miso_.close
      miso_ = null
    if clock_:
      clock_.close
      clock_ = null
/**
Installs the MAX31865 sensor.
*/
install --clock/int --miso/int --mosi/int --cs/int? -> providers.Provider:
  provider := providers.Provider NAME
      --major=MAJOR
      --minor=MINOR
      --open=:: Sensor_ --clock=clock --miso=miso --mosi=mosi --cs=cs
      --close=:: it.close
      --handlers=[providers.TemperatureHandler-v1]
  provider.install
  return provider
