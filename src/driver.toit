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
import resistance_to_temperature show *

/**
The Max31865 can run the SPI bus at up to 5MHz.

NOTE: The SPI device should be configured for SPI mode 1 or 3.
*/
MAX_BUS_SPEED ::= 5_000_000

class Driver:
  device_        /spi.Device
  registers_     /spi.Registers
  config_        /int := 0
  r_ref_         /float := 400.0
  zero_degree_r_ /float := 100.0

  constructor .device_/spi.Device:
    registers_ = device_.registers
    registers_.set_msb_write true
    configure

  set_ previous/int mask/int value/int -> int:
    assert: value & ~mask == 0
    return (previous & ~mask) | value

  /**
  Configure to 2, 3, or 4-wire mode, according to the
    schematics of your device.  See the data sheet for
    details.

  Set the digital filter to remove power supply noise
    at the given frequency.  $filter_hz must be either 50
    (default) or 60.

  Set the resistance of the reference resistor, Rref, in
    ohms.  Default is 400 ohms.

  Set the resistance of the RTD at zero degrees C.  Default
    is 0.25 times the resisitance of the reference resistor,
    or 100 ohms.
  */
  configure --wires/int=4 --filter_hz/int=50 --reference/num=400.0 --rtd_zero/num=(reference/4.0) -> none:
    r_ref_ = reference.to_float
    zero_degree_r_ = rtd_zero.to_float
    if not 2 <= wires <= 4: throw "ILLEGAL_ARGUMENT"
    if filter_hz != 50 and filter_hz != 60: throw "ILLEGAL_ARGUMENT"
    config_ = set_ config_ FILTER_MASK_
      filter_hz == 50 ? FILTER_50_HZ_ : FILTER_60_HZ_
    config_ = set_ config_ WIRE_CONFIGURATION_MASK_
      wires == 3 ? WIRE_CONFIGURATION_3_  : WIRE_CONFIGURATION_2_OR_4_
    registers_.write_u8 CONFIG_ config_
    clear_fault_

  set_bias_ value/bool -> none:
    config_ = set_ config_ V_BIAS_MASK_ (value ? V_BIAS_ON_ : V_BIAS_OFF_)
    registers_.write_u8 CONFIG_ config_
    // We need to prevent temperature measurements while the circuit
    // warms up.
    if value: sleep --ms=10

  /**
  Read the temperature, assuming an alpha of 0.00385055, corresponding
    to the IEC 751 standard.  Uses the Callendar-Van Dusen formula.
    Depends on an accurate calibration of the resistance at 0 degrees.
  */
  read_temperature -> float?:
    adc_code := read
    if not adc_code: return null
    r_rtd := (adc_code * r_ref_) / 0x8000
    return temperature_cvd_751 r_rtd zero_degree_r_

  /**
  Read the temperature in degrees C, assuming a linear
    resistance-temperature relation.  Uses the approximate
    algorithm from the data sheet.  Does not make use of
    the configuration of the reference resistance or the
    zero degrees resistance.  According to the data sheet
    this is accurate at 0C, gives -1.74C error at -100C,
    and -1.4C error at 100C.
  */
  read_simple_temperature -> float?:
    adc_code := read
    if not adc_code: return null
    return (adc_code / 32.0) - 256.0

  /**
  Read the ADC in one-shot mode.  Returns a value between
    0 and 0x7fff, inclusive.  A reading takes about 53ms in
    60Hz mode, and about 63ms in 50Hz mode.
  */
  read -> int?:
    clear_fault_
    set_bias_ true

    // Activation of one-shot mode is done by setting
    // the current status, but with the one-shot bit set.
    // The bit auto-resets after the reading.
    activate_code := set_ config_ ONE_SHOT_MASK_ ONE_SHOT_MODE_
    registers_.write_u8 CONFIG_ activate_code
    ms/int := ?
    if config_ & FILTER_MASK_ == FILTER_50_HZ_:
      ms = 63
    else:
      ms = 53
    sleep --ms=ms
    rtd := registers_.read_u16_be RTD_

    set_bias_ false

    if rtd & 1 != 0:
      return null
    return rtd >> 1

  clear_fault_:
    config := set_ config_ FAULT_STATUS_MASK_ FAULT_STATUS_CLEAR_
    registers_.write_u8 CONFIG_ config & 0b1101_0011

  // Register numbers.
  static CONFIG_       ::= 0
  static RTD_          ::= 1
  static HIGH_FAULT_   ::= 3
  static LOW_FAULT_    ::= 5
  static FAULT_STATUS_ ::= 7

  static REGISTER_READ_MODE_  ::= 0x00
  static REGISTER_WRITE_MODE_ ::= 0x80

  static FILTER_MASK_                ::= 0b0000_0001
  static FILTER_50_HZ_               ::= 0b0000_0001
  static FILTER_60_HZ_               ::= 0b0000_0000

  static FAULT_STATUS_MASK_          ::= 0b0000_0010
  static FAULT_STATUS_SET_           ::= 0b0000_0000
  static FAULT_STATUS_CLEAR_         ::= 0b0000_0010

  static FAULT_DETECTION_CYCLE_MASK_ ::= 0b0000_1100

  static WIRE_CONFIGURATION_MASK_    ::= 0b0001_0000
  static WIRE_CONFIGURATION_2_OR_4_  ::= 0b0000_0000
  static WIRE_CONFIGURATION_3_       ::= 0b0001_0000

  static ONE_SHOT_MASK_              ::= 0b0010_0000
  static ONE_SHOT_MODE_              ::= 0b0010_0000
  static CONTINUOUS_MODE_            ::= 0b0000_0000

  static CONVERSION_MODE_MASK_       ::= 0b0100_0000
  static CONVERSION_MODE_AUTO_       ::= 0b0100_0000
  static CONVERSION_MODE_TRIGGERED_  ::= 0b0000_0000

  static V_BIAS_MASK_                ::= 0b1000_0000
  static V_BIAS_ON_                  ::= 0b1000_0000
  static V_BIAS_OFF_                 ::= 0b0000_0000
