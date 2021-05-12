// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

/**
Driver for MAX31865 RTD-to-Digital Converter.
This is an SPI-connected digital-to-analog converter typically used for
  temperature measurement.  See
  https://datasheets.maximintegrated.com/en/ds/MAX31865.pdf
*/

import serial.protocols.spi as spi

/** The Max31865 can run the SPI bus at up to 5MHz. */
MAX_BUS_SPEED ::= 5_000_000

class Driver:
  device_        /spi.Device
  registers_     /spi.Registers
  config_        /int := 0
  on_            /bool := false
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
  configure --wires/int=3 --filter_hz/int=50 --reference/num=400.0 --rtd_zero/num=(reference/4.0) -> none:
    r_ref_ = reference.to_float
    zero_degree_r_ = rtd_zero.to_float
    if not 2 <= wires <= 4: throw "ILLEGAL_ARGUMENT"
    if filter_hz != 50 and filter_hz != 60: throw "ILLEGAL_ARGUMENT"
    config_ = set_ config_ FILTER_MASK_
      filter_hz == 50 ? FILTER_50_HZ_ : FILTER_60_HZ_
    config_ = set_ config_ WIRE_CONFIGURATION_MASK_
      wires == 3 ? WIRE_CONFIGURATION_3_  : WIRE_CONFIGURATION_2_OR_4_
    if on_:
      registers_.write_u8 CONFIG_ config_

  on -> none:
    config_ = set_ config_ V_BIAS_MASK_ V_BIAS_ON_
    registers_.write_u8 CONFIG_ config_
    on_ = true
    // TODO: We need to prevent temperature measurements while the circuit
    // warms up.

  off -> none:
    config_ = set_ config_ V_BIAS_MASK_ V_BIAS_OFF_
    registers_.write_u8 CONFIG_ config_
    on_ = false

  /**
  Read the temperature, assuming an alpha of 0.00385055, corresponding
    to the IEC 751 standard.  Uses the Callendar-Van Dusen formula.
    Depends on an accurate calibration of the resistance at 0 degrees.
  */
  read_temperature -> float:
    if not on_: throw "DEVICE_IS_OFF"
    adc_code := read
    r_rtd := (adc_code * r_ref_) / 0x8000
    // We use the Callendar-Van Dusen equation:
    // r_rtd / zero_degree_r_ = 1.0 + aT + bT² -100cT³ + cT⁴
    // a, b and c are derived from the standard IEC 751 alpha above:
    // Derivative of this function is:
    //   a + 2bT - 300cT² + 4cT³
    A ::= 3.9083e-3
    B ::= -5.775e-7
    C ::= -4.18301e-12
    temperature := newton_raphson_ --goal=r_rtd/zero_degree_r_
      --function=: | t |
        1.0
          + A * t
          + B * t * t
          - 100.0 * C * t * t * t
          + C * t * t * t * t
      --derivative=: | t |
        A
          + 2.0 * B * t
          - 300.0 * C * t * t
          + 4.0 * C * t * t * t
    return temperature

  /**
  Read the temperature in degrees C, assuming a linear
    resistance-temperature relation.  Uses the approximate
    algorithm from the data sheet.  Does not make use of
    the configuration of the reference resistance or the
    zero degrees resistance.  According to the data sheet
    this is accurate at 0C, gives -1.74C error at -100C,
    and -1.4C error at 100C.
  */
  read_simple_temperature -> float:
    adc_code := read
    return (adc_code / 32.0) - 256.0

  /**
  Read the ADC in one-shot mode.  Returns a value between
    0 and 0x7fff, inclusive.  A reading takes about 53ms in
    60Hz mode, and about 63ms in 50Hz mode.
  */
  read -> int:
    if not on_: throw "DEVICE_IS_OFF"
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
    sleep --ms=ms
    rtd := registers_.read_u16_be RTD_
    if rtd & 1 != 0:
      throw "HARDWARE_FAULT"
    return rtd >> 1

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

/**
Performs Newton-Raphson solving of a formula.  If you
  want to find x, but you only have y=f(x) then this
  uses an iterative process to find x from y.  You
  must supply a block that calculates f(x), and a block
  that calculates the derivative, f'(x).
*/
// TODO: Move this to its own package.
newton_raphson_ --initial/num=0.0 --goal/num=0.0 [--function] [--derivative]:
  x/float := initial.to_float
  previous := float.NAN
  100.repeat:
    top := (function.call x) - goal
    if top == 0: return x
    new_x := x - top / (derivative.call x)
    if new_x == x: return x
    if new_x == previous:
      // Oscillating around an answer.  Pick the best one.
      old_diff := (function.call x) - goal
      new_diff := (function.call new_x) - goal
      return old_diff.abs < new_diff.abs ? x : new_x
    previous = x
    x = new_x
  throw "DID_NOT_CONVERGE"

