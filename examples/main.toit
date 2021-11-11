// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

/**
Example for MAX31865 RTD-to-Digital Converter, an SPI-connected
  digital-to-analog converter typically used for temperature measurement.  See
  https://datasheets.maximintegrated.com/en/ds/MAX31865.pdf
*/

import gpio
import spi
import max31865

main:
  // Testing on hardware with a bug that requires us to hold
  // pin 15 up.
  dummy := gpio.Pin.out 15
  dummy.set 1

  bus := spi.Bus
    --mosi=gpio.Pin 13
    --miso=gpio.Pin 12
    --clock=gpio.Pin 14

  device := bus.device
    --cs=gpio.Pin 27
    --frequency=max31865.MAX_BUS_SPEED/8  // Conservative bus speed choice.
    --mode=1

  adc := max31865.Driver device

  10.repeat:
    print adc.read
    print adc.read_simple_temperature
    print adc.read_temperature

    sleep --ms=100
