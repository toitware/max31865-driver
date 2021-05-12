// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

/**
Example for MAX31865 RTD-to-Digital Converter, an SPI-connected
digital-to-analog converter typically used for temperature measurement.  See
https://datasheets.maximintegrated.com/en/ds/MAX31865.pdf
*/

import gpio
import serial.protocols.spi as spi
import max31865

main:
  bus := spi.Bus
    --mosi=gpio.Pin 13
    --miso=gpio.Pin 12
    --clock=gpio.Pin 14

  device := bus.device
    --cs=gpio.Pin 15
    --frequency=max31865.MAX_BUS_SPEED/4

  adc := max31865.Driver device

  adc.on

  sleep --ms=100

  adc.configure

  10.repeat:
    print adc.read
    print adc.read_simple_temperature
    print adc.read_temperature
