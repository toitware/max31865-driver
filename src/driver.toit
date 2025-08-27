// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

/**
Driver for MAX31865 RTD-to-Digital Converter.
This is an SPI-connected digital-to-analog converter typically used for
  temperature measurement.  See
  https://datasheets.maximintegrated.com/en/ds/MAX31865.pdf
*/

import spi
import resistance-to-temperature show *

/**
The Max31865 can run the SPI bus at up to 5MHz.

NOTE: The SPI device should be configured for SPI mode 1 or 3.
*/
MAX-BUS-SPEED ::= 5_000_000

class Driver:
  device_        /spi.Device
  registers_     /spi.Registers
  config_        /int := 0
  r-ref_         /float := 400.0
  zero-degree-r_ /float := 100.0

  constructor .device_/spi.Device:
    registers_ = device_.registers
    registers_.set-msb-write true
    configure

  set_ previous/int mask/int value/int -> int:
    assert: value & ~mask == 0
    return (previous & ~mask) | value

  /**
  Configure to 2, 3, or 4-wire mode, according to the
    schematics of your device.  See the data sheet for
    details.

  Set the digital filter to remove power supply noise
    at the given frequency.  $filter-hz must be either 50
    (default) or 60.

  Set the resistance of the reference resistor, Rref, in
    ohms.  Default is 400 ohms.

  Set the resistance of the RTD at zero degrees C.  Default
    is 0.25 times the resisitance of the reference resistor,
    or 100 ohms.
  */
  configure -> none
      --wires/int=4
      --filter-hz/int=50
      --reference/num=400.0
      --rtd-zero/num=(reference / 4.0):
    r-ref_ = reference.to-float
    zero-degree-r_ = rtd-zero.to-float
    if not 2 <= wires <= 4: throw "ILLEGAL_ARGUMENT"
    if filter-hz != 50 and filter-hz != 60: throw "ILLEGAL_ARGUMENT"
    config_ = set_ config_ FILTER-MASK_
      filter-hz == 50 ? FILTER-50-HZ_ : FILTER-60-HZ_
    config_ = set_ config_ WIRE-CONFIGURATION-MASK_
      wires == 3 ? WIRE-CONFIGURATION-3_  : WIRE-CONFIGURATION-2-OR-4_
    registers_.write-u8 CONFIG_ config_
    clear-fault_

  set-bias_ value/bool -> none:
    config_ = set_ config_ V-BIAS-MASK_ (value ? V-BIAS-ON_ : V-BIAS-OFF_)
    registers_.write-u8 CONFIG_ config_
    // We need to prevent temperature measurements while the circuit
    // warms up.
    if value: sleep --ms=10

  /**
  Reads the temperature.

  Assumes an alpha of 0.00385055, corresponding
    to the IEC 751 standard.  Uses the Callendar-Van Dusen formula.
    Depends on an accurate calibration of the resistance at 0 degrees.
  */
  read-temperature -> float?:
    adc-code := read
    if not adc-code: return null
    r-rtd := (adc-code * r-ref_) / 0x8000
    return temperature-cvd-751 r-rtd zero-degree-r_

  /**
  Reads the temperature in degrees C.

  Assumes a linear resistance-temperature relation.  Uses the approximate
    algorithm from the data sheet.  Does not make use of
    the configuration of the reference resistance or the
    zero degrees resistance.  According to the data sheet
    this is accurate at 0C, gives -1.74C error at -100C,
    and -1.4C error at 100C.
  */
  read-simple-temperature -> float?:
    adc-code := read
    if not adc-code: return null
    return (adc-code / 32.0) - 256.0

  /**
  Reads the ADC in one-shot mode.

  Returns a value between 0 and 0x7fff, inclusive.  A reading takes about
    53ms in 60Hz mode, and about 63ms in 50Hz mode.
  */
  read -> int?:
    clear-fault_
    set-bias_ true

    // Activation of one-shot mode is done by setting
    // the current status, but with the one-shot bit set.
    // The bit auto-resets after the reading.
    activate-code := set_ config_ ONE-SHOT-MASK_ ONE-SHOT-MODE_
    registers_.write-u8 CONFIG_ activate-code
    ms/int := ?
    if config_ & FILTER-MASK_ == FILTER-50-HZ_:
      ms = 63
    else:
      ms = 53
    sleep --ms=ms
    rtd := registers_.read-u16-be RTD_

    set-bias_ false

    if rtd & 1 != 0:
      return null
    return rtd >> 1

  clear-fault_:
    config := set_ config_ FAULT-STATUS-MASK_ FAULT-STATUS-CLEAR_
    registers_.write-u8 CONFIG_ config & 0b1101_0011

  // Register numbers.
  static CONFIG_       ::= 0
  static RTD_          ::= 1
  static HIGH-FAULT_   ::= 3
  static LOW-FAULT_    ::= 5
  static FAULT-STATUS_ ::= 7

  static REGISTER-READ-MODE_  ::= 0x00
  static REGISTER-WRITE-MODE_ ::= 0x80

  static FILTER-MASK_                ::= 0b0000_0001
  static FILTER-50-HZ_               ::= 0b0000_0001
  static FILTER-60-HZ_               ::= 0b0000_0000

  static FAULT-STATUS-MASK_          ::= 0b0000_0010
  static FAULT-STATUS-SET_           ::= 0b0000_0000
  static FAULT-STATUS-CLEAR_         ::= 0b0000_0010

  static FAULT-DETECTION-CYCLE-MASK_ ::= 0b0000_1100

  static WIRE-CONFIGURATION-MASK_    ::= 0b0001_0000
  static WIRE-CONFIGURATION-2-OR-4_  ::= 0b0000_0000
  static WIRE-CONFIGURATION-3_       ::= 0b0001_0000

  static ONE-SHOT-MASK_              ::= 0b0010_0000
  static ONE-SHOT-MODE_              ::= 0b0010_0000
  static CONTINUOUS-MODE_            ::= 0b0000_0000

  static CONVERSION-MODE-MASK_       ::= 0b0100_0000
  static CONVERSION-MODE-AUTO_       ::= 0b0100_0000
  static CONVERSION-MODE-TRIGGERED_  ::= 0b0000_0000

  static V-BIAS-MASK_                ::= 0b1000_0000
  static V-BIAS-ON_                  ::= 0b1000_0000
  static V-BIAS-OFF_                 ::= 0b0000_0000
