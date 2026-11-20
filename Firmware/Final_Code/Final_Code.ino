/* Teeeeeeng
 * ============================================================================
 *  Wearable Physiological Monitoring System - ESP32 Firmware (Wrist-Optimized
 * v4.1)
 * ============================================================================
 *  Thesis: "Wearable Technology for Personalized Well-Being Among
 *           University Students: Development and Validation of
 *           Physiological Signals"
 *
 *  Hardware Platform: ESP32 WROOM-32
 *
 *  Integrated Sensors:
 *    1. MAX30102 Heart Rate (PPG) Sensor -> I2C (0x57) on GPIO 21/22
 *    2. Grove GSR v1.2 Sensor           -> GPIO 34 (ADC1_CH6, Analog)
 *    3. MLX90614 IR Temperature Sensor  -> I2C (0x5A) on GPIO 21/22
 *    4. MPU6050 6-Axis IMU              -> I2C (0x68) on GPIO 21/22
 *
 *  Additional Components:
 *    5. KY-016 RGB LED Module           -> R=GPIO18, G=GPIO19, B=GPIO5
 *    6. Battery Voltage Monitoring      -> GPIO 32 (ADC1_CH4, Analog)
 *
 *  v4.1 Changes from v4.0:
 *  -----------------------------------------------------------------------
 *  ARCHITECTURE CHANGE (Approach 1A — Edge + Client Computing):
 *    - Firmware retains sensor acquisition, preprocessing, windowed
 *      feature extraction, HRV computation, and baseline calibration
 *      (EDGE COMPUTING on ESP32).
 *    - REMOVED on-device 5-tree ensemble classification.
 *    - Feature vector (top 15 WESAD features + HRV metrics) is now
 *      transmitted via BLE Stress characteristic as JSON.
 *    - The Flutter mobile app receives the feature vector and performs
 *      all classification, stress index computation, and chronic
 *      detection (CLIENT COMPUTING).
 *    - Benefits: faster ML model iteration without re-flashing,
 *      richer contextual data on mobile, parallel edge+client pipeline
 *      for comparison in thesis.
 *
 *  RETAINED from v4.0:
 *    - 60-second sliding window feature extraction (edge computing)
 *    - HRV computation: RMSSD, SDNN, pNN50 from IBI buffer
 *    - User-specific baseline calibration (5-min calm period)
 *    - Status RGB LED (battery only; no stress colour on the wrist)
 *    - MPU6050 calibration (HW gyro offsets + SW accel offsets + DLPF)
 *    - MLX90614 EEPROM emissivity + dual-EMA temperature pipeline
 *    - PPG filter pipeline with custom + SparkFun fallback beat detection
 *    - Serial data output, plotter mode, CSV stream
 *
 *  REMOVED from v4.0:
 *    - 5-tree ensemble classification over BLE (now done by app)
 *    - Chronic stress detection on-device (now done by app)
 *
 *  MLX90614 CALIBRATION (retained from v4.0):
 *    - 833-point composite calibration from 4-cluster validation.
 *    - Composite: Y = 0.5870 × X_raw + 17.216
 *
 *  GSR CALIBRATION (updated):
 *    - 10-subject pooled OLS, 2429 valid points, R² = 0.7932
 *    - R = ((4095 + 2×ADC) × 10000) / (2275 − ADC)
 *    - calc_uS = 1,000,000 / R
 *    - poly_uS = 0.3460 × calc_uS + 4.0800
 *
 *  Version: 4.1 (Approach 1A — Edge feature extraction + Client classification)
 *  Authors: Calunsag, Manubag & Opao
 *  Date: March 2026
 * ============================================================================
 */

#include "MAX30105.h"  // SparkFun MAX3010x library (works for MAX30102)
#include "heartRate.h" // SparkFun beat detection on IR channel
#include "stress_model_manual.h" // Edge computing: feature extraction + baseline
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <Wire.h>

enum SensorStatus : int;

// ========================= BLE GATT SERVER CONFIG ========================
// Service and Characteristic UUIDs per Thesis Section 3.3.4.1.
// Using 128-bit UUIDs to avoid collision with standard BT SIG profiles.
// =========================================================================
// BLE device name — the serial suffix is appended at runtime from the ESP32
// chip ID so every physical unit advertises a unique, human-readable name.
// Format: "PHYSIOPANO-XXXXXX" where XXXXXX = last 3 bytes of the factory
// MAC address as uppercase hex (e.g. "PHYSIOPANO-A3F204").
// The base prefix is kept short so the full 18-char name fits BLE ad packet.
#define BLE_DEVICE_NAME_PREFIX "PHYSIOPANO-"
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_HR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define CHAR_HRV_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define CHAR_GSR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26aa"
#define CHAR_TEMP_UUID "beb5483e-36e1-4688-b7f5-ea07361b26ab"
#define CHAR_MOTION_UUID "beb5483e-36e1-4688-b7f5-ea07361b26ac"
#define CHAR_STRESS_UUID "beb5483e-36e1-4688-b7f5-ea07361b26ad"
// RTT latency measurement ping/echo characteristic (phone writes, ESP32 echoes)
#define CHAR_PING_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26ae"

BLEServer *pServer = nullptr;
BLECharacteristic *pCharHR = nullptr;
BLECharacteristic *pCharHRV = nullptr;
BLECharacteristic *pCharGSR = nullptr;
BLECharacteristic *pCharTemp = nullptr;
BLECharacteristic *pCharMotion = nullptr;
BLECharacteristic *pCharStress = nullptr;
BLECharacteristic *pCharPing = nullptr;
bool bleDeviceConnected = false;
bool bleOldDeviceConnected = false;

// BLE connection callbacks
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) override {
    bleDeviceConnected = true;
    Serial.println(F("[BLE] Client connected"));
  }
  void onDisconnect(BLEServer *pServer) override {
    bleDeviceConnected = false;
    Serial.println(F("[BLE] Client disconnected — restarting advertising"));
  }
};

// RTT latency measurement — phone writes a ping, ESP32 echoes it immediately.
// Zero processing delay: the received bytes are echoed back unchanged via notify().
// Only the phone's clock is used (T1 before write, T2 after echo received),
// so clock-domain differences between ESP32 millis() and phone epoch-ms are irrelevant.
class PingCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) override {
    // Echo the received bytes back unchanged — zero processing delay.
    pChar->setValue(pChar->getData(), pChar->getLength());
    pChar->notify();
  }
};

// ========================= MAX30102 CONFIG ============================
MAX30105 max30102;
bool max30102Found = false;

#define MAX30102_LED_BRIGHTNESS 0xFF
#define MAX30102_SAMPLE_AVG 8
#define MAX30102_LED_MODE 2
#define MAX30102_SAMPLE_RATE 400
#define MAX30102_PULSE_WIDTH 411
#define MAX30102_ADC_RANGE 16384
#define MAX30102_IR_WRIST_THRESH 3000
#define MAX30102_WRIST_LOST_COUNT 30

// ========================= MLX90614 TEMPERATURE CONFIG ================
// v3.8.3 TEMPERATURE PIPELINE (datasheet-correct):
// -----------------------------------------------------------------------
// EMISSIVITY HANDLING:
//   The MLX90614 has a built-in emissivity register at EEPROM address 0x04.
//   Factory default = 0xFFFF = epsilon 1.0 (perfect blackbody).
//   The sensor's internal DSP uses this in its T^4-domain computation:
//     V_IR(Ta,To) = A * (To^4 - Ta^4)  [datasheet eq, Section 4.1.8]
//   When we write epsilon=0.95 to EEPROM, the DSP correctly solves for To
//   knowing that only 95% of the IR flux comes from the object (rest is
//   reflected environment). This is MUCH more accurate than external
//   Stefan-Boltzmann correction on the linearized output.
//
//   Per datasheet Section 5.6 + EEPROM Table 8:
//     EEPROM[0x04] = round(65535 * epsilon)
//     epsilon=0.95 -> round(65535*0.95) = 62258 = 0xF332
//     epsilon=0.97 -> round(65535*0.97) = 63569 = 0xF851
//     epsilon=0.98 -> round(65535*0.98) = 64224 = 0xFAE0
//
//   The EEPROM write procedure (datasheet Section 4.1.3.3.1):
//     1. Write 0x0000 to erase the cell
//     2. Wait >= 10ms
//     3. Write the new value
//     4. Wait >= 10ms
//     5. Read back and verify
//   EEPROM has 100K write cycles — writing once per power-on is fine.
//
// FILTER CHAIN (order matters):
//   MLX90614 output (already emissivity-corrected by internal DSP)
//   -> ambient temperature compensation
//   -> median-of-5 (impulse noise removal)
//   -> linear calibration (maps to reference thermometer scale)
//   -> outlier gate (rejects jumps > threshold from current EMA)
//   -> dual-stage EMA (fast for tracking, slow for stable output)
//   -> rate-of-change limiter (max 0.1°C/sec)
//   -> output
// -----------------------------------------------------------------------

// Emissivity for human wrist skin (literature: 0.95-0.98)
// Written to MLX90614 EEPROM 0x04 on startup
float skinEmissivity = 0.95f;
bool emissivityWritten = false;

// Ambient temperature compensation
const float TEMP_AMB_REF = 25.0f;
const float TEMP_AMB_COEFF = 0.10f;

// Dual EMA filters.
// MLX_EMA_SLOW_ALPHA was 0.04 (τ ≈ 24 s) which attenuated the peripheral
// vasoconstriction-driven temp drop used by tree2 and the weighted stress
// index.  Raising it to 0.08 (τ ≈ 12 s) preserves the stress-relevant
// downward trend while still suppressing high-frequency thermal noise.
// Reference: Gillan et al. (2017) measured average skin-temp drop latency
// of ~15 s after Stroop stressor onset — a 12 s time-constant captures this.
const float MLX_EMA_FAST_ALPHA = 0.35f;  // Faster tracking (was 0.15 — τ≈6.7s, now τ≈2.9s)
const float MLX_EMA_SLOW_ALPHA = 0.18f;  // Faster slow trend (was 0.08 — τ≈12.5s, now τ≈5.6s)
// Outlier gate threshold (calibrated output space).
// With composite slope 0.587 (vs old 0.2056), the output range is ~2.85x wider.
// Old threshold 0.6°C caught ~2.9°C raw glitches; scaled: 0.6 × 2.855 ≈ 1.7°C.
const float MLX_OUTLIER_THRESHOLD = 1.7f;

const int MLX_WARMUP_SAMPLES = 10;

float tempEmaFast = -999.0f;
float tempEmaSlow = -999.0f;
bool tempEmaInit = false;
int tempWarmupCount = 0;

// Rate-of-change limiter — max calibrated output change per second.
// With composite slope 0.587 (2.85x old), output swings are wider.
// Old: 0.10°C/s ÷ 0.2056 = 0.49°C/s raw.  New: 0.49 × 0.587 = 0.29°C/s output.
// Using 0.25°C/s — slightly tighter to catch power-on transients.
const float TEMP_MAX_RATE_PER_SEC = 0.8f;  // Relaxed rate limit (was 0.25°C/s — too slow for rapid skin changes)
float tempLastOutput = -999.0f;
unsigned long tempLastOutputMs = 0;

// Median-of-5 filter
const int TEMP_MEDIAN_SIZE = 5;
float tempMedianBuf[TEMP_MEDIAN_SIZE];
int tempMedianIdx = 0;
int tempMedianFilled = 0;

void sortFloatArray(float *arr, int n) {
  for (int i = 1; i < n; i++) {
    float key = arr[i];
    int j = i - 1;
    while (j >= 0 && arr[j] > key) {
      arr[j + 1] = arr[j];
      j--;
    }
    arr[j + 1] = key;
  }
}

float tempMedianFilter(float newVal) {
  tempMedianBuf[tempMedianIdx] = newVal;
  tempMedianIdx = (tempMedianIdx + 1) % TEMP_MEDIAN_SIZE;
  if (tempMedianFilled < TEMP_MEDIAN_SIZE)
    tempMedianFilled++;
  if (tempMedianFilled < 3)
    return newVal;
  float sorted[TEMP_MEDIAN_SIZE];
  int count = tempMedianFilled;
  memcpy(sorted, tempMedianBuf, count * sizeof(float));
  sortFloatArray(sorted, count);
  return sorted[count / 2];
}

float applyAmbientCompensation(float skinC, float ambientC) {
  return skinC + TEMP_AMB_COEFF * (TEMP_AMB_REF - ambientC);
}

// Linear calibration — 833-point multi-range validation (4 clusters)
// Reference: iCare Infrared Thermometer (Model E66) vs MLX90614 (ε=0.95)
// Conditions: Low Range, Normal Rest, Normal Active, High Fever
//   MLX raw range: ~29.6–39.1°C  →  iCare reference: 33.6–41.1°C
//
// COMPOSITE CALIBRATION:
//   The validation CSV captured the old-calibrated serial output (not raw
//   sensor values), so the iCare regression Y=2.855*X-66.76 mapped
//   old-calibrated → reference.  To apply as a single pipeline stage on
//   the raw-after-ambient-comp input, we compose both:
//     Y = 2.855 * (0.2056 * X_raw + 29.4141) - 66.76
//       = 0.5870 * X_raw + 17.216
//
// Verification at cluster means (raw → output vs iCare):
//   Low Range:     29.6°C → 34.59°C  (ref 34.34, err +0.25°C)
//   Normal Rest:   31.8°C → 35.88°C  (ref 35.89, err −0.01°C)
//   Normal Active: 34.8°C → 37.65°C  (ref 37.76, err −0.11°C)
//   High Fever:    39.1°C → 40.16°C  (ref 40.16, err −0.00°C)
//
// R²=0.954, Post-cal MAE=0.322°C, N=833
// Date: March 2026
const float TEMP_CAL_SLOPE = 0.586980f;
const float TEMP_CAL_INTERCEPT = 17.2160f;
// Empirical fine-tune offset from 10-subject validation vs iCare E66 thermometer.
// Constant-offset correction (linear regression slope ~0, R²=0.02 due to narrow
// reference range 36.2-36.4°C). Firmware output reads ~0.53°C high on average.
// MAE after correction: 0.1444°C  |  Std dev of residuals: 0.1794°C
// Calibration_Report_HR_Temp.pdf — Per-subject means, N=10, pairs=579
float tempFineTuneOffset = -0.5317f;

float tempLinearCalibrate(float correctedC) {
  return TEMP_CAL_SLOPE * correctedC + TEMP_CAL_INTERCEPT + tempFineTuneOffset;
}

// Rate-of-change limiter
float tempRateLimiter(float newVal) {
  unsigned long nowMs = millis();
  if (tempLastOutput < -900.0f) {
    tempLastOutput = newVal;
    tempLastOutputMs = nowMs;
    return newVal;
  }
  float dtSec = (nowMs - tempLastOutputMs) / 1000.0f;
  if (dtSec < 0.001f)
    dtSec = 0.001f;
  float maxChange = TEMP_MAX_RATE_PER_SEC * dtSec;
  float delta = newVal - tempLastOutput;
  if (delta > maxChange)
    delta = maxChange;
  if (delta < -maxChange)
    delta = -maxChange;
  tempLastOutput += delta;
  tempLastOutputMs = nowMs;
  return tempLastOutput;
}

// ========================= I2C ADDRESSES =============================
#define MLX90614_ADDRESS 0x5A
#define MPU6050_ADDRESS 0x68

// ========================= MLX90614 SMBus EEPROM FUNCTIONS ===========

uint8_t crc8_mlx(uint8_t *data, uint8_t len) {
  uint8_t crc = 0;
  for (uint8_t i = 0; i < len; i++) {
    crc ^= data[i];
    for (uint8_t bit = 0; bit < 8; bit++) {
      if (crc & 0x80)
        crc = (crc << 1) ^ 0x07;
      else
        crc <<= 1;
    }
  }
  return crc;
}

bool mlx90614ReadWord(uint8_t command, uint16_t *result) {
  Wire.beginTransmission(MLX90614_ADDRESS);
  Wire.write(command);
  if (Wire.endTransmission(false) != 0)
    return false;
  Wire.requestFrom((uint8_t)MLX90614_ADDRESS, (uint8_t)3);
  if (Wire.available() < 3)
    return false;
  uint8_t lsb = Wire.read();
  uint8_t msb = Wire.read();
  uint8_t pec = Wire.read();
  uint8_t pec_data[5];
  pec_data[0] = (MLX90614_ADDRESS << 1);
  pec_data[1] = command;
  pec_data[2] = (MLX90614_ADDRESS << 1) | 1;
  pec_data[3] = lsb;
  pec_data[4] = msb;
  uint8_t calcPec = crc8_mlx(pec_data, 5);
  if (calcPec != pec) {
    Serial.print(F("[MLX] PEC mismatch: got 0x"));
    Serial.print(pec, HEX);
    Serial.print(F(" expected 0x"));
    Serial.println(calcPec, HEX);
  }
  *result = ((uint16_t)msb << 8) | lsb;
  return true;
}

bool mlx90614WriteWord(uint8_t command, uint16_t data) {
  uint8_t lsb = data & 0xFF;
  uint8_t msb = (data >> 8) & 0xFF;
  uint8_t pec_data[4];
  pec_data[0] = (MLX90614_ADDRESS << 1);
  pec_data[1] = command;
  pec_data[2] = lsb;
  pec_data[3] = msb;
  uint8_t pec = crc8_mlx(pec_data, 4);

  Wire.beginTransmission(MLX90614_ADDRESS);
  Wire.write(command);
  Wire.write(lsb);
  Wire.write(msb);
  Wire.write(pec);
  return (Wire.endTransmission() == 0);
}

bool setMLX90614Emissivity(float epsilon) {
  if (epsilon < 0.1f || epsilon > 1.0f) {
    Serial.println(F("[MLX] Emissivity must be 0.10-1.00"));
    return false;
  }

  uint16_t emissReg = (uint16_t)(epsilon * 65535.0f + 0.5f);
  uint8_t eeCommand = 0x24;

  uint16_t currentVal = 0;
  if (mlx90614ReadWord(eeCommand, &currentVal)) {
    if (currentVal == emissReg) {
      Serial.print(F("[MLX] Emissivity already set to "));
      Serial.print(epsilon, 3);
      Serial.print(F(" (0x"));
      Serial.print(emissReg, HEX);
      Serial.println(F(")"));
      return true;
    }
  }

  Serial.print(F("[MLX] Writing emissivity "));
  Serial.print(epsilon, 3);
  Serial.print(F(" = 0x"));
  Serial.print(emissReg, HEX);
  Serial.println(F(" to EEPROM[0x04]..."));

  if (!mlx90614WriteWord(eeCommand, 0x0000)) {
    Serial.println(F("[MLX] EEPROM erase FAILED"));
    return false;
  }
  delay(15);

  uint16_t readBack = 0xFFFF;
  mlx90614ReadWord(eeCommand, &readBack);
  if (readBack != 0x0000) {
    Serial.print(F("[MLX] Erase verify FAILED, read: 0x"));
    Serial.println(readBack, HEX);
  }

  if (!mlx90614WriteWord(eeCommand, emissReg)) {
    Serial.println(F("[MLX] EEPROM write FAILED"));
    return false;
  }
  delay(15);

  readBack = 0;
  mlx90614ReadWord(eeCommand, &readBack);
  if (readBack == emissReg) {
    Serial.print(F("[MLX] Emissivity set OK: 0x"));
    Serial.println(readBack, HEX);
    return true;
  } else {
    Serial.print(F("[MLX] Write verify MISMATCH: wrote 0x"));
    Serial.print(emissReg, HEX);
    Serial.print(F(" read 0x"));
    Serial.println(readBack, HEX);
    return false;
  }
}

float readMLX90614Emissivity() {
  uint16_t val = 0;
  if (mlx90614ReadWord(0x24, &val)) {
    return (float)val / 65535.0f;
  }
  return -1.0f;
}

// ========================= PIN DEFINITIONS ===========================
#define HEARTRATE_PIN 35
#define GSR_PIN 34
#define VBAT_PIN 32
#define SDA_PIN 21
#define SCL_PIN 22
#define RGB_RED_PIN 18
#define RGB_GREEN_PIN 19
#define RGB_BLUE_PIN 5

// ========================= MLX90614 REGISTERS ========================
#define MLX90614_TA 0x06
#define MLX90614_TOBJ1 0x07

// ========================= MPU6050 REGISTERS =========================
#define MPU6050_PWR_MGMT_1 0x6B
#define MPU6050_ACCEL_XOUT_H 0x3B
#define MPU6050_WHO_AM_I 0x75
#define MPU6050_GYRO_CONFIG 0x1B
#define MPU6050_ACCEL_CONFIG 0x1C
#define MPU6050_CONFIG 0x1A     // DLPF config register
#define MPU6050_SMPLRT_DIV 0x19 // Sample rate divider

// MPU6050 Gyroscope hardware offset registers (16-bit signed, R/W)
// Per Register Map Rev 4.2: these offsets are subtracted from the gyro
// sensor data before it reaches the output registers.
// At FS_SEL=0 (±250 dps), 1 LSB = 1 raw gyro LSB.
#define MPU6050_XG_OFFS_USRH 0x13
#define MPU6050_XG_OFFS_USRL 0x14
#define MPU6050_YG_OFFS_USRH 0x15
#define MPU6050_YG_OFFS_USRL 0x16
#define MPU6050_ZG_OFFS_USRH 0x17
#define MPU6050_ZG_OFFS_USRL 0x18

// MPU6050 Accelerometer offset registers (hardware trim)
// NOTE: Bit 0 of the low byte is reserved for temperature compensation.
// We use SOFTWARE offsets for accel to avoid corrupting the TC bit.
#define MPU6050_XA_OFFS_H 0x06
#define MPU6050_XA_OFFS_L_TC 0x07
#define MPU6050_YA_OFFS_H 0x08
#define MPU6050_YA_OFFS_L_TC 0x09
#define MPU6050_ZA_OFFS_H 0x0A
#define MPU6050_ZA_OFFS_L_TC 0x0B

// ========================= MPU6050 CALIBRATION CONFIG ================
// Number of samples for startup calibration.
// Internal sample rate = 1kHz / (1 + SMPLRT_DIV) = 1kHz / 5 = 200 Hz → new
// sample every 5ms.  We read every 6ms (delay(6)) to guarantee a fresh sample
// each iteration.  1000 samples × 6ms = 6 seconds of truly independent data.
// Reference: Tedaldi et al. (2014), IEEE ICRA — recommends ≥5s of static data
// per position for bias estimation with MEMS IMUs.
const int MPU_CAL_SAMPLES = 1000;

// Discard initial samples to let the DLPF settle after reset/config.
// DLPF=3: BW=44Hz → time constant 1/(2π×44) ≈ 3.6ms.  5× settling = 18ms.
// 30 samples × 6ms = 180ms — well past any transient.
const int MPU_CAL_DISCARD = 30;

// Software accelerometer offsets (in raw ADC units, ±2g range)
// These are subtracted from raw readings in readMPU6050().
// At ±2g: 16384 LSB/g. Target at rest: ax=0, ay=0, az=+16384.
// Pre-deployment calibration offsets — 10-trial static bias estimation
// (Tedaldi et al., 2014). Measured 2026-05-03, device flat, N=1000/trial.
// Mean gyro bias: (-0.9924, -0.2962, -0.0870) dps  SD: (0.0090, 0.0057, 0.0061)
// Mean accel bias: (0.09687, -0.03503, -0.03502) g  SD: (0.00006, 0.00005, 0.00020)
int16_t mpuAccelOffsetX = 1587;
int16_t mpuAccelOffsetY = -574;
int16_t mpuAccelOffsetZ = -574;

// Gyro offsets are written to hardware registers, but we keep a copy
// for display/diagnostics.
int16_t mpuGyroOffsetX = 130;
int16_t mpuGyroOffsetY = 39;
int16_t mpuGyroOffsetZ = 11;

bool mpuCalibrated = true;

// ========================= SAMPLING INTERVALS ========================
const unsigned long GSR_INTERVAL = 500;
const unsigned long TEMP_INTERVAL = 1000;
const unsigned long MPU_INTERVAL = 200;
const unsigned long PRINT_INTERVAL = 1000;
const unsigned long BATTERY_INTERVAL = 5000;
const unsigned long BLE_NOTIFY_INTERVAL = 1000; // BLE update rate = 1 Hz

bool plotterMode = false;
bool csvStreamMode = false;

// Stress classification state (edge-computed, also sent as features to app)
StressResult currentStress = {};
bool stressModelReady = false;

// CSV header for serial streaming (SD removed, still useful for serial CSV)
const char CSV_HEADER[] =
    "timestamp_ms,uptime_s,worn,hr_bpm,hr_valid,hr_raw_adc,hr_dc_removed,hr_"
    "filtered,hr_threshold,hr_sqi,hr_stability_cv,hr_ibi_count,gsr_raw_adc,gsr_"
    "voltage,gsr_resistance_ohm,gsr_smoothed_ohm,gsr_baseline_ohm,gsr_"
    "calibrated_us,temp_skin_c,temp_calibrated_c,temp_ambient_c,temp_stability_"
    "sd,accel_x_g,accel_y_g,accel_z_g,accel_mag_g,gyro_x_dps,gyro_y_dps,gyro_z_"
    "dps,mpu_temp_c,battery_v,battery_smoothed_v,battery_pct,hr_status,gsr_"
    "status,temp_status,mpu_status";

// ========================= PPG PIPELINE (v3.8.2 — unchanged) =========
const float PPG_HP_ALPHA = 0.95;
float ppgHpPrev = 0.0, ppgRawPrev = 0.0;
bool ppgHpInit = false;

const float PPG_LP1_ALPHA = 0.45;  // Wrist: ~3.6 Hz cutoff passes 1–3 Hz heartbeat band
float ppgLp1Filtered = 0.0;
bool ppgLp1Init = false;

const float PPG_LP2_ALPHA = 0.35;  // Wrist: ~2.8 Hz cutoff; lower values kill peak amplitude
float ppgLp2Filtered = 0.0;
bool ppgLp2Init = false;

const int PPG_MA_SIZE = 3;  // Keep MA narrow — wider MA adds delay and flattens peaks
float ppgMaBuf[PPG_MA_SIZE] = {0};
int ppgMaIdx = 0;
bool ppgMaFull = false;
float ppgMaOutput = 0.0;

const unsigned long PPG_REFRACTORY_MS = 300;
const float PPG_THRESH_ENTER = 0.30;
const float PPG_THRESH_EXIT = 0.12;
const int PPG_ADAPT_WINDOW = 40;
const float PPG_ADAPT_DECAY = 0.85;
float ppgRunningMin = 9999.0, ppgRunningMax = -9999.0;
int ppgAdaptCounter = 0;
unsigned long ppgLastPeakTime = 0;
bool ppgAboveThreshold = false;
float ppgCurrentThreshold = 0.0;
float ppgExitThreshold = 0.0;
float ppgPeakValue = -9999.0;
unsigned long ppgPeakTimeMs = 0;

// ---- Slope zero-crossing peak detector ----
float ppgPrevFiltered = 0.0f;
bool ppgPrevFilteredInit = false;
float ppgSlopeSmoothed = 0.0f;
float ppgSlopePrev = 0.0f;
const float PPG_SLOPE_EMA_ALPHA = 0.35f;
const float PPG_PEAK_GATE_FRAC = 0.30f;  // Relaxed for wrist (weaker signal than finger)

// Warmup counter — suppress false beats during filter settling
int ppgWarmupCount = 0;
const int PPG_WARMUP_SAMPLES = 30;

const int PPG_IBI_HISTORY = 10;
unsigned long ppgIbiHistory[PPG_IBI_HISTORY];
int ppgIbiIndex = 0, ppgIbiCount = 0;
const float PPG_IBI_OUTLIER_PCT = 0.50;

float ppgDcRemoved = 0.0, ppgFiltered = 0.0;
int ppgRawLatest = 0;
uint32_t ppgIrRaw = 0;
uint32_t ppgRedRaw = 0;

// ========================= SKIN DETECTION (Red/IR ratio) ==============
// Hemoglobin in skin absorbs RED (660nm) more than IR (880nm), giving
// Red/IR DC ratio of ~0.3-0.85 for skin.  Non-biological objects reflect
// both wavelengths similarly, giving ratio ~0.9-1.1.
// This discriminates actual wrist contact from objects near the sensor.
const float SKIN_RATIO_MIN = 0.20f;   // Min Red/IR for skin (dark pigment)
const float SKIN_RATIO_MAX = 0.85f;   // Max Red/IR for skin
const int SKIN_CONFIRM_SAMPLES = 75;
const int SKIN_REJECT_SAMPLES = 150;  // ~3.0s to reject (avoids flicker)
float ppgRedIrRatioEma = 0.0f;
bool ppgRedIrRatioInit = false;
int skinConfirmCount = 0;
int skinRejectCount = 0;
bool skinConfirmed = false;

const float PPG_BPM_EMA_ALPHA = 0.25;

float ppgBpmEma = -1.0;

const float PPG_MOTION_THRESH_G = 0.25;  // Wrist: relaxed motion gate (was 0.15)
int wristLowCount = 0;

// ========================= AUTO-GAIN DISPLAY =========================
const int PPG_DISPLAY_WINDOW = 150;
float ppgDispMin = 9999.0;
float ppgDispMax = -9999.0;
int ppgDispCounter = 0;
float ppgDispMinHold = 0.0;
float ppgDispMaxHold = 1.0;
int ppgWaveNorm = 500;
bool ppgBeatMarker = false;

int ppgAutoGainNormalize(float val) {
  float range = ppgDispMaxHold - ppgDispMinHold;
  if (range < 0.01)
    return 500;
  float normalized = (val - ppgDispMinHold) / range;
  return constrain((int)(normalized * 900.0 + 50.0), 0, 1000);
}

void ppgDisplayUpdate(float val) {
  if (val < ppgDispMin)
    ppgDispMin = val;
  if (val > ppgDispMax)
    ppgDispMax = val;
  ppgDispCounter++;
  if (ppgDispCounter >= PPG_DISPLAY_WINDOW) {
    float newRange = ppgDispMax - ppgDispMin;
    if (newRange > 0.01) {
      ppgDispMinHold = 0.3 * ppgDispMin + 0.7 * ppgDispMinHold;
      ppgDispMaxHold = 0.3 * ppgDispMax + 0.7 * ppgDispMaxHold;
    }
    ppgDispMin = 9999.0;
    ppgDispMax = -9999.0;
    ppgDispCounter = 0;
  }
  ppgWaveNorm = ppgAutoGainNormalize(ppgMaOutput);
}

// ========================= HEART RATE ================================
const int HR_RAW_BUFFER_SIZE = 50;
int hrRawBuffer[HR_RAW_BUFFER_SIZE];
int hrBufferIndex = 0;
bool hrBufferFull = false;
const int HR_BPM_HISTORY_SIZE = 10;
uint8_t hrBpmHistory[HR_BPM_HISTORY_SIZE];
int hrBpmHistoryIndex = 0;
bool hrBpmHistoryFull = false;

// ========================= MLX90614 =================================
int tempConsecutiveErrors = 0;
const int TEMP_MAX_ERRORS = 3;
const int TEMP_HISTORY_SIZE = 10;
float tempHistory[TEMP_HISTORY_SIZE];
int tempHistoryIndex = 0;
bool tempHistoryFull = false;

// ========================= MPU6050 ==================================
float accelX, accelY, accelZ;
float gyroX, gyroY, gyroZ;
float mpuTemperature;

// ========================= GSR ======================================
const int GSR_SAMPLES_PER_READ = 10;
const float GSR_EMA_ALPHA = 0.3;
float gsrEmaFiltered = -1.0;
float currentGSRResistanceSmoothed = 0.0;
const int GSR_HISTORY_SIZE = 10;
float gsrHistory[GSR_HISTORY_SIZE];
int gsrHistoryIndex = 0;
bool gsrHistoryFull = false;

// ========================= DEVICE SERIAL NUMBER =====================
// Derived from the last 3 bytes of the ESP32 factory MAC address (eFuse).
// This is globally unique across all ESP32 chips — no NVS writes needed.
// Included in the BLE device name and every charHR JSON packet so the
// mobile app and research data can be tied to a specific physical unit.
// Format: 6 uppercase hex digits (e.g. "A3F204").
char deviceSerial[7] = "000000";  // 6 hex chars + null terminator

void generateDeviceSerial() {
  uint64_t chipId = ESP.getEfuseMac();
  // Use bytes 0-2 (lower 24 bits) — these are the device-specific part of
  // the MAC; bytes 3-5 are the Espressif OUI and are identical across units.
  uint8_t b0 = (chipId >>  0) & 0xFF;
  uint8_t b1 = (chipId >>  8) & 0xFF;
  uint8_t b2 = (chipId >> 16) & 0xFF;
  snprintf(deviceSerial, sizeof(deviceSerial), "%02X%02X%02X", b0, b1, b2);
}

// ========================= BATTERY ==================================
const float VBAT_DIVIDER_RATIO = 2.0;
const float VBAT_FULL = 4.2, VBAT_EMPTY = 3.0;
const float BAT_EMA_ALPHA = 0.1;
float batEmaFiltered = -1.0;
float batteryVoltage = 0.0, batteryVoltageSmoothed = 0.0;
int batteryPercent = 0;

// ========================= TIMING ===================================
unsigned long lastGSRRead = 0, lastTempRead = 0;
unsigned long lastMPURead = 0, lastPrint = 0, lastBatteryRead = 0;
unsigned long lastBLENotify = 0, lastStressUpdate = 0;
unsigned long systemStartTime = 0;
unsigned long lastBeatTime = 0;

// ========================= LATENCY / RESPONSE-TIME INSTRUMENTATION ==========
// These are updated each cycle and embedded in BLE JSON so the mobile app can
// display and log per-layer timing without needing a debugger.
// ---------------------------------------------------------------------------
uint32_t gsrAcqUs      = 0;   // GSR analogRead loop duration (µs)
uint32_t tempAcqUs     = 0;   // MLX90614 I2C read duration (µs)
uint32_t mpuAcqUs      = 0;   // MPU6050 I2C read duration (µs)
uint32_t featExtractMs = 0;   // stressModelUpdate() duration (ms)
uint32_t bleSeqNum     = 0;   // monotonic BLE packet counter (for drop detection)

// ========================= SENSOR STATUS =============================
enum SensorStatus : int {
  SENSOR_OK = 0,
  SENSOR_INIT_FAIL = 1,
  SENSOR_READ_ERROR = 2,
  SENSOR_RECOVERING = 3,
  SENSOR_WAITING = 4
};

// ========================= CURRENT READINGS ==========================
uint8_t currentHeartRate = 0;
bool heartRateValid = false;
float hrSignalQuality = 0.0;
SensorStatus hrStatus = SENSOR_WAITING;

int currentGSRRaw = 0;
float currentGSRResistance = 0.0;
float currentGSRVoltage = 0.0;
float gsrBaseline = 0.0;
float currentGSRMicroSiemens = 0.0;
SensorStatus gsrStatus = SENSOR_OK;

float currentTempAmbient = -999.0, currentTempObject = -999.0;
float currentTempCalibrated = -999.0, tempStability = 0.0;
SensorStatus tempStatus = SENSOR_WAITING;

float accelMagnitude = 1.0;  // Start at 1 g (standard gravity) so motionSafe=true until MPU6050 provides real data
SensorStatus mpuStatus = SENSOR_WAITING;

bool deviceWorn = false;
unsigned long packetCount = 0;

// =====================================================================
//                         EMA HELPER
// =====================================================================
float applyEMA(float &filtered, float newValue, float alpha) {
  if (filtered < 0.0)
    filtered = newValue;
  else
    filtered = alpha * newValue + (1.0 - alpha) * filtered;
  return filtered;
}

// =====================================================================
//          PPG FILTER PIPELINE (v3.8.2 — 2nd-order LP)
// =====================================================================
float ppgHighPass(int rawAdc) {
  if (!ppgHpInit) {
    ppgHpPrev = 0.0;
    ppgRawPrev = (float)rawAdc;
    ppgHpInit = true;
    return 0.0;
  }
  float hp = PPG_HP_ALPHA * (ppgHpPrev + (float)rawAdc - ppgRawPrev);
  ppgHpPrev = hp;
  ppgRawPrev = (float)rawAdc;
  return hp;
}

float ppgLowPass1(float s) {
  if (!ppgLp1Init) {
    ppgLp1Filtered = s;
    ppgLp1Init = true;
    return s;
  }
  ppgLp1Filtered = PPG_LP1_ALPHA * s + (1.0 - PPG_LP1_ALPHA) * ppgLp1Filtered;
  return ppgLp1Filtered;
}

float ppgLowPass2(float s) {
  if (!ppgLp2Init) {
    ppgLp2Filtered = s;
    ppgLp2Init = true;
    return s;
  }
  ppgLp2Filtered = PPG_LP2_ALPHA * s + (1.0 - PPG_LP2_ALPHA) * ppgLp2Filtered;
  return ppgLp2Filtered;
}

float ppgMovingAvg(float s) {
  ppgMaBuf[ppgMaIdx] = s;
  ppgMaIdx = (ppgMaIdx + 1) % PPG_MA_SIZE;
  if (!ppgMaFull && ppgMaIdx == 0)
    ppgMaFull = true;
  if (!ppgMaFull)
    return s;
  float sum = 0;
  for (int i = 0; i < PPG_MA_SIZE; i++)
    sum += ppgMaBuf[i];
  ppgMaOutput = sum / PPG_MA_SIZE;
  return ppgMaOutput;
}

// =====================================================================
//          PEAK DETECTION (v3.8 — UNCHANGED)
// =====================================================================
unsigned long ppgDetectPeak(float filteredSample, unsigned long nowMs) {
  // Adaptive envelope (still needed for peak gate)
  if (filteredSample > ppgRunningMax)
    ppgRunningMax = filteredSample;
  if (filteredSample < ppgRunningMin)
    ppgRunningMin = filteredSample;
  ppgAdaptCounter++;
  if (ppgAdaptCounter >= PPG_ADAPT_WINDOW) {
    ppgAdaptCounter = 0;
    ppgRunningMax = ppgRunningMax * PPG_ADAPT_DECAY +
                    filteredSample * (1.0 - PPG_ADAPT_DECAY);
    ppgRunningMin = ppgRunningMin * PPG_ADAPT_DECAY +
                    filteredSample * (1.0 - PPG_ADAPT_DECAY);
  }
  float amplitude = ppgRunningMax - ppgRunningMin;
  ppgCurrentThreshold = ppgRunningMin + amplitude * PPG_THRESH_ENTER;
  ppgExitThreshold = ppgRunningMin + amplitude * PPG_THRESH_EXIT;

  // Warmup — suppress false beats while filters settle
  if (ppgWarmupCount < PPG_WARMUP_SAMPLES) {
    ppgWarmupCount++;
    ppgPrevFiltered = filteredSample;
    ppgPrevFilteredInit = true;
    return 0;
  }

  // Slope zero-crossing detector
  if (!ppgPrevFilteredInit) {
    ppgPrevFiltered = filteredSample;
    ppgPrevFilteredInit = true;
    return 0;
  }
  float rawSlope = filteredSample - ppgPrevFiltered;
  ppgPrevFiltered = filteredSample;
  ppgSlopeSmoothed = PPG_SLOPE_EMA_ALPHA * rawSlope +
                     (1.0f - PPG_SLOPE_EMA_ALPHA) * ppgSlopeSmoothed;

  // Detect positive → negative zero-crossing (local maximum)
  if (ppgSlopePrev > 0.0f && ppgSlopeSmoothed <= 0.0f) {
    // Peak gate: only accept if signal is above 40% of envelope
    float gate = ppgRunningMin + amplitude * PPG_PEAK_GATE_FRAC;
    if (amplitude >= 0.02f && filteredSample >= gate) {
      unsigned long elapsed = nowMs - ppgLastPeakTime;
      if (ppgLastPeakTime > 0 && elapsed >= PPG_REFRACTORY_MS) {
        ppgLastPeakTime = nowMs;
        ppgSlopePrev = ppgSlopeSmoothed;
        return elapsed;
      } else if (ppgLastPeakTime == 0) {
        ppgLastPeakTime = nowMs;
      }
    }
  }
  ppgSlopePrev = ppgSlopeSmoothed;
  return 0;
}

// =====================================================================
//          IBI + BPM (v3.8.2)
// =====================================================================
unsigned long ppgGetMedianIBI() {
  if (ppgIbiCount < 2)
    return 0;
  int count = ppgIbiCount;
  unsigned long sorted[PPG_IBI_HISTORY];
  memcpy(sorted, ppgIbiHistory, count * sizeof(unsigned long));
  for (int i = 1; i < count; i++) {
    unsigned long key = sorted[i];
    int j = i - 1;
    while (j >= 0 && sorted[j] > key) {
      sorted[j + 1] = sorted[j];
      j--;
    }
    sorted[j + 1] = key;
  }
  return sorted[count / 2];
}

void ppgStoreIBI(unsigned long ibiMs) {
  if (ibiMs < 300 || ibiMs > 1500)
    return;
  if (ppgIbiCount >= 3) {
    unsigned long med = ppgGetMedianIBI();
    if (med > 0) {
      long diff = (long)ibiMs - (long)med;
      if (diff < 0)
        diff = -diff;
      if (diff > (long)(med * PPG_IBI_OUTLIER_PCT))
        return;
    }
  }
  ppgIbiHistory[ppgIbiIndex] = ibiMs;
  ppgIbiIndex = (ppgIbiIndex + 1) % PPG_IBI_HISTORY;
  if (ppgIbiCount < PPG_IBI_HISTORY)
    ppgIbiCount++;
}

uint8_t ppgMedianBPM() {
  if (ppgIbiCount < 2)
    return 0;
  int count = ppgIbiCount;
  unsigned long sorted[PPG_IBI_HISTORY];
  memcpy(sorted, ppgIbiHistory, count * sizeof(unsigned long));
  for (int i = 1; i < count; i++) {
    unsigned long key = sorted[i];
    int j = i - 1;
    while (j >= 0 && sorted[j] > key) {
      sorted[j + 1] = sorted[j];
      j--;
    }
    sorted[j + 1] = key;
  }
  unsigned long medIbi;
  if (count % 2 == 0)
    medIbi = (sorted[count / 2 - 1] + sorted[count / 2]) / 2;
  else
    medIbi = sorted[count / 2];
  return (uint8_t)constrain(60000UL / medIbi, 40, 200);
}

// =====================================================================
//          PLOTTER OUTPUT
// =====================================================================
void outputPlotterLine() {
  Serial.print("PPG_Wave:");
  Serial.print(ppgWaveNorm);
  float range = ppgDispMaxHold - ppgDispMinHold;
  int threshNorm = 500;
  if (range > 0.01) {
    threshNorm = constrain(
        (int)((ppgCurrentThreshold - ppgDispMinHold) / range * 900.0 + 50.0), 0,
        1000);
  }
  Serial.print(",Threshold:");
  Serial.print(threshNorm);
  Serial.print(",Beat:");
  Serial.print(ppgBeatMarker ? 1200 : 0);
  Serial.print(",BPM:");
  Serial.print(heartRateValid ? currentHeartRate : 0);
  Serial.print(",Worn:");
  Serial.print(deviceWorn ? 100 : 0);
  Serial.print(",SkinRatio:");
  Serial.println((int)(ppgRedIrRatioEma * 100));
}

// =====================================================================
//        CSV ROW (Serial only — no SD)
// =====================================================================
void writeCSVRow() {
  if (!csvStreamMode)
    return; // Only output if CSV stream is active
  unsigned long nowMs = millis();
  unsigned long uptimeSec = (nowMs - systemStartTime) / 1000;
  float hrStab = computeHRStability();
  String row = "";
  row.reserve(400);
  row += String(nowMs);
  row += ",";
  row += String(uptimeSec);
  row += ",";
  row += String(deviceWorn ? 1 : 0);
  row += ",";
  row += String(currentHeartRate);
  row += ",";
  row += String(heartRateValid ? 1 : 0);
  row += ",";
  row += String(ppgRawLatest);
  row += ",";
  row += String(ppgDcRemoved, 2);
  row += ",";
  row += String(ppgFiltered, 2);
  row += ",";
  row += String(ppgCurrentThreshold, 2);
  row += ",";
  row += String(hrSignalQuality, 3);
  row += ",";
  row += String(hrStab >= 0 ? hrStab : -1.0, 2);
  row += ",";
  row += String(ppgIbiCount);
  row += ",";
  row += String(currentGSRRaw);
  row += ",";
  row += String(currentGSRVoltage, 4);
  row += ",";
  row += String(currentGSRResistance, 1);
  row += ",";
  row += String(currentGSRResistanceSmoothed, 1);
  row += ",";
  row += String(gsrBaseline, 1);
  row += ",";
  row += String(currentGSRMicroSiemens, 4);
  if (currentTempObject != -999.0) {
    row += ",";
    row += String(currentTempObject, 2);
    row += ",";
    row += String(currentTempCalibrated, 2);
    row += ",";
    row += String(currentTempAmbient, 2);
    row += ",";
    row += String(tempStability >= 0 ? tempStability : -1.0, 4);
  } else {
    row += ",,,,";
  }
  row += ",";
  row += String(accelX, 4);
  row += ",";
  row += String(accelY, 4);
  row += ",";
  row += String(accelZ, 4);
  row += ",";
  row += String(accelMagnitude, 4);
  row += ",";
  row += String(gyroX, 2);
  row += ",";
  row += String(gyroY, 2);
  row += ",";
  row += String(gyroZ, 2);
  row += ",";
  row += String(mpuTemperature, 1);
  row += ",";
  row += String(batteryVoltage, 3);
  row += ",";
  row += String(batteryVoltageSmoothed, 3);
  row += ",";
  row += String(batteryPercent);
  row += ",";
  row += String((int)hrStatus);
  row += ",";
  row += String((int)gsrStatus);
  row += ",";
  row += String((int)tempStatus);
  row += ",";
  row += String((int)mpuStatus);
  Serial.println(row);
}

// =====================================================================
//           BLE GATT NOTIFICATION (Thesis Figure 3.14)
// =====================================================================
// Sends JSON-formatted sensor data + stress classification via BLE
// to the mobile application.  Each characteristic is updated and
// notified independently so the app can subscribe selectively.
// =====================================================================

void sendBLENotifications() {
  if (!bleDeviceConnected)
    return;

  // --- HR characteristic ---
  // esp_ms = millis() at send-time; app uses Δesp_ms vs Δapp_rx to compute BLE jitter.
  // seq = monotonic counter; app detects dropped packets by gaps in this value.
  // "sn" = device serial (6-char hex from chip MAC).
  // Included in every charHR packet so the app can verify on the very first
  // notification that it is connected to the expected wearable unit.
  String hrJson = "{\"bpm\":" + String(currentHeartRate) +
                  ",\"valid\":" + String(heartRateValid ? "true" : "false") +
                  ",\"sqi\":" + String(hrSignalQuality, 2) +
                  ",\"esp_ms\":" + String(millis()) +
                  ",\"seq\":" + String(bleSeqNum++) +
                  ",\"sn\":\"" + String(deviceSerial) + "\"}";
  pCharHR->setValue(hrJson.c_str());
  pCharHR->notify();

  // --- HRV characteristic (computed inline from ppgIbiHistory) ---
  float rmssd = -1.0f, sdnn = -1.0f, pnn50 = -1.0f;
  bool hrvValid = false;
  // Need ≥5 IBIs for meaningful HRV. Reconstruct chronological order from the
  // circular buffer so RMSSD successive differences are computed correctly.
  int ibiN = (ppgIbiCount < PPG_IBI_HISTORY) ? ppgIbiCount : PPG_IBI_HISTORY;
  if (ibiN >= 5) {
    // Oldest sample is at ppgIbiIndex (wraps around). Unroll into linear array.
    unsigned long ordered[PPG_IBI_HISTORY];
    int startIdx = (ppgIbiCount < PPG_IBI_HISTORY) ? 0
                   : ppgIbiIndex; // oldest slot after ring wrap
    for (int i = 0; i < ibiN; i++)
      ordered[i] = ppgIbiHistory[(startIdx + i) % PPG_IBI_HISTORY];

    // Mean IBI
    double sumIBI = 0;
    for (int i = 0; i < ibiN; i++) sumIBI += ordered[i];
    double meanIBI = sumIBI / ibiN;
    // SDNN: population std dev of all IBIs
    double sumSqDev = 0;
    for (int i = 0; i < ibiN; i++) {
      double d = (double)ordered[i] - meanIBI;
      sumSqDev += d * d;
    }
    sdnn = (float)sqrt(sumSqDev / ibiN);
    // RMSSD + pNN50: successive IBI differences in chronological order
    double sumSqDiff = 0;
    int nn50 = 0;
    for (int i = 1; i < ibiN; i++) {
      long diff = (long)ordered[i] - (long)ordered[i - 1];
      sumSqDiff += (double)diff * diff;
      if (labs(diff) > 50) nn50++;
    }
    rmssd = (float)sqrt(sumSqDiff / (ibiN - 1));
    pnn50 = (float)nn50 / (ibiN - 1) * 100.0f;
    hrvValid = true;
  }
  String hrvJson = "{\"rmssd\":" + String(hrvValid ? rmssd : -1.0f, 1) +
                   ",\"sdnn\":" + String(hrvValid ? sdnn : -1.0f, 1) +
                   ",\"pnn50\":" + String(hrvValid ? pnn50 : -1.0f, 1) + "}";
  pCharHRV->setValue(hrvJson.c_str());
  pCharHRV->notify();

  // --- GSR characteristic ---
  // acq = analogRead loop duration in microseconds (sensor acquisition time)
  String gsrJson = "{\"us\":" + String(currentGSRMicroSiemens, 2) +
                   ",\"raw\":" + String(currentGSRRaw) +
                   ",\"acq\":" + String(gsrAcqUs) + "}";
  pCharGSR->setValue(gsrJson.c_str());
  pCharGSR->notify();

  // --- Temperature characteristic ---
  // acq = MLX90614 I2C read duration in microseconds
  String tempJson = "{\"skin\":" + String(currentTempObject, 2) +
                    ",\"ambient\":" + String(currentTempAmbient, 2) +
                    ",\"acq\":" + String(tempAcqUs) + "}";
  pCharTemp->setValue(tempJson.c_str());
  pCharTemp->notify();

  // --- Motion characteristic ---
  // acq = MPU6050 I2C read duration in microseconds
  String motionJson = "{\"ax\":" + String(accelX, 3) +
                      ",\"ay\":" + String(accelY, 3) +
                      ",\"az\":" + String(accelZ, 3) +
                      ",\"mag\":" + String(accelMagnitude, 3) +
                      ",\"acq\":" + String(mpuAcqUs) + "}";
  pCharMotion->setValue(motionJson.c_str());
  pCharMotion->notify();

  // --- Feature Vector characteristic (v4.1: edge-extracted features for app)
  // --- Pack top 15 WESAD features + metadata for client computing
  float featureBuf[FEATURE_VECTOR_SIZE];
  packFeaturesForBLE(featureBuf);
  HRVMetrics hrvBle = computeHRV(&ibiWindow);

  String featJson = "{\"f\":[" + String(featureBuf[0], 2);
  for (int i = 1; i < FEATURE_VECTOR_SIZE; i++) {
    featJson += "," + String(featureBuf[i], 2);
  }
  featJson += "],\"hr\":" + String(currentHeartRate) +
              ",\"rmssd\":" + String(hrvBle.valid ? hrvBle.rmssd : -1.0f, 1) +
              ",\"sdnn\":" + String(hrvBle.valid ? hrvBle.sdnn : -1.0f, 1) +
              ",\"pnn50\":" + String(hrvBle.valid ? hrvBle.pnn50 : -1.0f, 1) +
              ",\"cal\":" + String(baseline.calibrated ? "true" : "false") +
              ",\"bat\":" + String(batteryPercent) +
              ",\"feat_ms\":" + String(featExtractMs) + "}";
  pCharStress->setValue(featJson.c_str());
  pCharStress->notify();
}

// =====================================================================
//           STATUS LED (device state only)
// =====================================================================
// PHYSIOPANO hackathon build: the LED no longer shows a stress colour.
// A glowing "stress" light is a label others can read on your wrist,
// which is covert monitoring. It now shows only device state (battery).
// Change detection runs in the app, against the wearer's own baseline.
// =====================================================================

void updateStressLED() {
  updateBatteryLED();
}

// =====================================================================
//                              SETUP
// =====================================================================
void setup() {
  Serial.begin(115200);
  delay(100);
  systemStartTime = millis();

  // Generate unique serial from chip MAC (must be first — used in BLE name)
  generateDeviceSerial();

  Serial.println();
  Serial.println(
      F("================================================================"));
  Serial.println(
      F("  Wearable Physiological Monitoring System - ESP32 Firmware"));
  Serial.println(
      F("  Thesis: Personalized Well-Being Among University Students"));
  Serial.println(
      F("================================================================"));
  Serial.print(F("  Device Serial: "));
  Serial.println(deviceSerial);
  Serial.println(
      F("  Sensors: MAX30102 (HR) | Grove GSR v1.2 | MLX90614 | MPU6050"));
  Serial.println(F("  Extras:  KY-016 RGB LED | VBAT Monitor | BLE GATT"));
  Serial.println(F("  v4.0: Stress model + BLE + HRV + Feature extraction"));
  Serial.println(
      F("================================================================"));
  Serial.println();

  pinMode(RGB_RED_PIN, OUTPUT);
  pinMode(RGB_GREEN_PIN, OUTPUT);
  pinMode(RGB_BLUE_PIN, OUTPUT);
  setRGBColor(0, 0, 0);
  Serial.println(F("[INIT] KY-016 RGB LED on GPIO 18/19/5 - Ready"));

  // I2C bus recovery: clock out any slave holding SDA low after a hard reset
  // or mid-transaction upload. Generates 9 clock pulses then a STOP condition.
  pinMode(SCL_PIN, OUTPUT);
  pinMode(SDA_PIN, INPUT_PULLUP);
  for (int _i2cPulse = 0; _i2cPulse < 9; _i2cPulse++) {
    digitalWrite(SCL_PIN, HIGH); delayMicroseconds(10);
    digitalWrite(SCL_PIN, LOW);  delayMicroseconds(10);
  }
  // STOP condition: SDA rises while SCL is HIGH
  pinMode(SDA_PIN, OUTPUT);
  digitalWrite(SDA_PIN, LOW);  delayMicroseconds(10);
  digitalWrite(SCL_PIN, HIGH); delayMicroseconds(10);
  digitalWrite(SDA_PIN, HIGH); delayMicroseconds(10);
  // Hand control back to Wire
  pinMode(SCL_PIN, INPUT);
  pinMode(SDA_PIN, INPUT);

  Wire.begin(SDA_PIN, SCL_PIN);
  Wire.setClock(100000);

  // --- MLX90614 init + EEPROM emissivity ---
  Serial.print(F("[INIT] MLX90614 IR Temperature Sensor... "));
  if (initMLX90614()) {
    Serial.println(F("OK (I2C addr 0x5A)"));
    tempStatus = SENSOR_OK;

    float currentEpsilon = readMLX90614Emissivity();
    Serial.print(F("[INIT] MLX90614 current EEPROM emissivity: "));
    if (currentEpsilon > 0) {
      Serial.println(currentEpsilon, 4);
    } else {
      Serial.println(F("READ ERROR"));
    }

    Serial.print(F("[INIT] Target skin emissivity: "));
    Serial.println(skinEmissivity, 3);
    emissivityWritten = setMLX90614Emissivity(skinEmissivity);
    if (!emissivityWritten) {
      Serial.println(F("[INIT] WARNING: EEPROM emissivity write failed!"));
      Serial.println(F("[INIT]   Sensor will use its current EEPROM value."));
    }
  } else {
    Serial.println(F("FAILED - Check wiring to GPIO 21/22"));
    tempStatus = SENSOR_INIT_FAIL;
  }

  Serial.print(F("[INIT] MAX30102 Heart Rate Sensor... "));
  for (int _hrAttempt = 0; _hrAttempt < 3 && !max30102Found; _hrAttempt++) {
    if (_hrAttempt > 0) {
      Serial.print(F(" retry "));
      Serial.print(_hrAttempt);
      Serial.print(F("..."));
      delay(200);
    }
    if (max30102.begin(Wire, I2C_SPEED_STANDARD)) {
      max30102Found = true;
      max30102.setup(MAX30102_LED_BRIGHTNESS, MAX30102_SAMPLE_AVG,
                     MAX30102_LED_MODE, MAX30102_SAMPLE_RATE,
                     MAX30102_PULSE_WIDTH, MAX30102_ADC_RANGE);
      max30102.setPulseAmplitudeRed(0xFF);
      max30102.setPulseAmplitudeIR(0xFF);
      max30102.setPulseAmplitudeGreen(0);
      Serial.println(F("OK (I2C addr 0x57)"));
      Serial.print(F("         Rate: "));
      Serial.print(MAX30102_SAMPLE_RATE);
      Serial.print(F("sps  Avg: "));
      Serial.print(MAX30102_SAMPLE_AVG);
      Serial.print(F("x  Eff: "));
      Serial.print(MAX30102_SAMPLE_RATE / MAX30102_SAMPLE_AVG);
      Serial.println(F("sps"));
      hrStatus = SENSOR_WAITING;
    }
  }
  if (!max30102Found) {
    Serial.println(F("FAILED (check wiring to GPIO 21/22, power-cycle device)"));
    hrStatus = SENSOR_INIT_FAIL;
  }

  // --- MPU6050 init + DLPF + calibration ---
  Serial.print(F("[INIT] MPU6050 IMU Sensor... "));
  if (initMPU6050()) {
    Serial.println(F("OK (0x68)"));
    mpuStatus = SENSOR_OK;

    // Apply pre-deployment hardcoded offsets (10-trial calibration, 2026-05-03).
    // Skips runtime calibration — device no longer needs to be held still on boot.
    // Send 'i' via Serial to re-run runtime calibration if needed.
    mpuWriteWord(MPU6050_XG_OFFS_USRH, mpuGyroOffsetX);
    mpuWriteWord(MPU6050_YG_OFFS_USRH, mpuGyroOffsetY);
    mpuWriteWord(MPU6050_ZG_OFFS_USRH, mpuGyroOffsetZ);
    Serial.println(F("[IMU]  Pre-deployment offsets applied. Gyro HW + Accel SW ready."));
  } else {
    Serial.println(F("FAILED"));
    mpuStatus = SENSOR_INIT_FAIL;
  }

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);
  memset(hrRawBuffer, 0, sizeof(hrRawBuffer));
  memset(hrBpmHistory, 0, sizeof(hrBpmHistory));
  memset(tempHistory, 0, sizeof(tempHistory));
  memset(gsrHistory, 0, sizeof(gsrHistory));
  memset(ppgIbiHistory, 0, sizeof(ppgIbiHistory));
  for (int i = 0; i < TEMP_MEDIAN_SIZE; i++)
    tempMedianBuf[i] = -999.0f;

  Serial.println();
  Serial.println(F("[INIT] Pipeline summary:"));
  Serial.println(
      F("  PPG: HP(0.95)->LP1(0.45)->LP2(0.35)->detect | MA3->display"));
  Serial.println(F("  BPM: 10-IBI median + EMA(0.25) + 50% outlier gate"));
  Serial.println(F("  GSR: 10-avg + EMA(0.3) + poly3 cal (R2=0.896)"));
  Serial.print(F("  TEMP: EEPROM emiss("));
  Serial.print(skinEmissivity, 2);
  Serial.println(F(") -> AmbComp -> Median5 -> LinCal(833pt,composite) -> "
                   "DualEMA -> RateLim"));
  Serial.println(F("  IMU: DLPF(42Hz) + HW gyro offsets + SW accel offsets"));
  Serial.println(F("  BAT: 10-avg + EMA(0.1)"));
  Serial.println(F("  HRV: RMSSD + SDNN + pNN50 from IBI buffer"));
  Serial.println(
      F("  EDGE: 60s window -> feature extraction -> BLE feature vector"));
  Serial.println(
      F("  CLIENT: App receives features -> 5-tree ensemble classification"));
  Serial.println(
      F("  BLE: GATT server, 6 characteristics, JSON notify @ 1 Hz"));
  Serial.println();
  Serial.println(F("Commands: 'c<val>'=temp offset | 'e<val>'=emissivity | "
                   "'i'=IMU recal | 'b'=reset baseline | 's'=status | "
                   "'p'=plotter | 'd'=CSV | 'h'=help"));
  Serial.println(
      F("----------------------------------------------------------------"));

  readBattery();
  updateBatteryLED();

  // --- BLE GATT Server Init (Thesis Section 3.3.4.1) ---
  Serial.println(F("[INIT] BLE GATT Server..."));
  // Device name = prefix + serial (e.g. "PHYSIOPANO-A3F204").
  // Each unit advertises a unique name so participants in a group study can
  // identify their own wearable and the app can reject foreign devices.
  char bleName[32];
  snprintf(bleName, sizeof(bleName), "%s%s", BLE_DEVICE_NAME_PREFIX, deviceSerial);
  BLEDevice::init(bleName);
  Serial.print(F("[INIT] BLE name: ")); Serial.println(bleName);
  // Request 256-byte MTU to accommodate JSON payloads (~200 bytes).
  // Default MTU is 23 bytes which silently truncates our JSON strings.
  // The actual negotiated MTU depends on the client (mobile app).
  BLEDevice::setMTU(256);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  // numHandles = 30: each characteristic needs 3 handles (declaration + value + CCCD).
  // 7 characteristics × 3 = 21 + 1 service declaration = 22 minimum. Use 30 for headroom.
  BLEService *pService = pServer->createService(BLEUUID(SERVICE_UUID), 30);

  pCharHR = pService->createCharacteristic(
      CHAR_HR_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pCharHR->addDescriptor(new BLE2902());

  pCharHRV = pService->createCharacteristic(
      CHAR_HRV_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pCharHRV->addDescriptor(new BLE2902());

  pCharGSR = pService->createCharacteristic(
      CHAR_GSR_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pCharGSR->addDescriptor(new BLE2902());

  pCharTemp = pService->createCharacteristic(
      CHAR_TEMP_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pCharTemp->addDescriptor(new BLE2902());

  pCharMotion = pService->createCharacteristic(
      CHAR_MOTION_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pCharMotion->addDescriptor(new BLE2902());

  pCharStress = pService->createCharacteristic(
      CHAR_STRESS_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pCharStress->addDescriptor(new BLE2902());

  // Ping/echo characteristic for RTT latency measurement.
  // Phone writes any bytes → ESP32 immediately echoes via notify().
  pCharPing = pService->createCharacteristic(
      CHAR_PING_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY);
  if (pCharPing == nullptr) {
    Serial.println(F("[BLE] ERROR: pCharPing createCharacteristic FAILED — too many GATT handles?"));
  } else {
    pCharPing->addDescriptor(new BLE2902());
    pCharPing->setCallbacks(new PingCallbacks());
    Serial.println(F("[BLE] Ping characteristic registered OK"));
  }

  pService->start();

  // Primary advertisement: service UUID (guaranteed in every beacon)
  // Scan response: complete device name (returned on active scan request)
  // Splitting them ensures service UUID is always visible for app filtering
  // even if the scan response hasn't been received yet.
  BLEAdvertisementData adData;
  adData.setFlags(0x06);  // LE General Discoverable | BR/EDR Not Supported
  adData.setCompleteServices(BLEUUID(SERVICE_UUID));

  BLEAdvertisementData scanResp;
  scanResp.setName(bleName);

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->setAdvertisementData(adData);
  pAdvertising->setScanResponseData(scanResp);
  pAdvertising->setMinPreferred(0x06);
  BLEDevice::startAdvertising();
  Serial.print(F("[INIT] BLE advertising as: ")); Serial.println(bleName);

  // v4.1: Stress model removed — classification handled by mobile app
  Serial.println(
      F("[INIT] AI classification delegated to mobile app (Approach 1)"));

  Serial.println(F("=== DATA OUTPUT START ===\n"));
}

// =====================================================================
//                            MAIN LOOP
// =====================================================================
void loop() {
  // MAX30102 effective sample rate = 400sps / 8 averaging = 50sps (new sample every 20ms).
  // Calling getIR() faster than that returns the same stale FIFO value, which makes
  // the HP/LP filter chain output 0 slope → zero-crossing detector never fires → no BPM.
  // Gate to 50Hz so the filter always sees a genuinely new sample each call.
  static unsigned long lastHRSample = 0;
  unsigned long now = millis();
  if (now - lastHRSample >= 20) {
    lastHRSample = now;
    sampleHeartRate();
  }
  if (now - lastGSRRead >= GSR_INTERVAL) {
    lastGSRRead = now;
    uint32_t _gsrT0 = micros();
    readGSR();
    gsrAcqUs = micros() - _gsrT0;
  }
  if (now - lastTempRead >= TEMP_INTERVAL) {
    lastTempRead = now;
    uint32_t _tmpT0 = micros();
    readMLX90614();
    tempAcqUs = micros() - _tmpT0;
  }
  if (now - lastMPURead >= MPU_INTERVAL) {
    lastMPURead = now;
    uint32_t _mpuT0 = micros();
    readMPU6050();
    mpuAcqUs = micros() - _mpuT0;
  }
  if (now - lastBatteryRead >= BATTERY_INTERVAL) {
    lastBatteryRead = now;
    readBattery();
  }

  // --- Edge computing: feature extraction (every second) ---
  if (now - lastStressUpdate >= STRESS_UPDATE_INTERVAL) {
    lastStressUpdate = now;
    // Run full pipeline: baseline cal + feature extraction + on-device classify
    // Classification result used for LED; feature vector sent to app via BLE
    uint32_t _featT0 = millis();
    currentStress = stressModelUpdate(accelMagnitude, PPG_MOTION_THRESH_G, now);
    featExtractMs = millis() - _featT0;
    stressModelReady = (currentStress.stressIndex >= 0.0f);

    // Stress-aware LED (from edge-computed classification)
    if (stressModelReady) {
      updateStressLED();
    } else if (!baseline.calibrated) {
      static bool calPulse = false;
      calPulse = !calPulse;
      setRGBColor(0, calPulse ? 100 : 30, calPulse ? 100 : 30);
    } else {
      updateBatteryLED();
    }
  }

  // --- BLE GATT notification (1 Hz when connected) ---
  if (bleDeviceConnected && (now - lastBLENotify >= BLE_NOTIFY_INTERVAL)) {
    lastBLENotify = now;
    sendBLENotifications();
  }

  // Handle BLE reconnection (non-blocking — Bug 9 fix)
  if (!bleDeviceConnected && bleOldDeviceConnected) {
    // Don't use delay() here — it blocks sampleHeartRate() and causes
    // missed PPG beats.  The BLE stack handles cleanup asynchronously;
    // just restart advertising on the next loop iteration.
    BLEDevice::startAdvertising();
    Serial.println(F("[BLE] Restarting advertising..."));
    bleOldDeviceConnected = false;
  }
  if (bleDeviceConnected && !bleOldDeviceConnected) {
    bleOldDeviceConnected = true;
  }

  // --- Serial output ---
  if (now - lastPrint >= PRINT_INTERVAL) {
    lastPrint = now;
    writeCSVRow(); // outputs only if csvStreamMode is on
    if (!plotterMode && !csvStreamMode)
      outputDataPacket();
  }

  // --- Battery deep sleep DISABLED for prototyping ---
  // Deep sleep is removed during prototyping because:
  //   (a) USB-powered bench testing reports false low-battery readings
  //   (b) esp_deep_sleep without battery circuit triggers unrecoverable sleep
  // Re-enable for field deployment by uncommenting the block below.
  // TODO: Restore for final deployment (see Thesis Figure 3.14)
  /*
  if (batteryPercent <= 5 && batteryVoltageSmoothed > 0.5) {
    Serial.println(F("[SYS] Battery critically low — entering deep sleep"));
    if (bleDeviceConnected) {
      String sleepMsg = "{\"event\":\"deep_sleep\",\"battery\":" +
  String(batteryPercent) + "}"; pCharStress->setValue(sleepMsg.c_str());
      pCharStress->notify();
      delay(200);
    }
    esp_sleep_enable_ext0_wakeup(GPIO_NUM_0, 0);
    esp_sleep_enable_timer_wakeup(30ULL * 60 * 1000000);
    esp_deep_sleep_start();
  }
  */

  handleSerialCommands();
}

// =====================================================================
//   HEART RATE (v3.8.2 — unchanged)
// =====================================================================
unsigned long lastAcceptedBeatTime = 0;
const unsigned long BEAT_REFRACTORY_MS = 300;
unsigned long lastCustomPipelineBeatTime = 0;
const unsigned long SPARKFUN_FALLBACK_TIMEOUT_MS = 1500;  // Faster fallback to SparkFun detector (was 3000ms)

void processBeat(unsigned long beatTimestamp) {
  if (lastAcceptedBeatTime > 0 &&
      (beatTimestamp - lastAcceptedBeatTime) < BEAT_REFRACTORY_MS)
    return;
  long delta = beatTimestamp - lastAcceptedBeatTime;
  lastAcceptedBeatTime = beatTimestamp;
  if (delta <= 0 || delta > 3000)
    return;
  float bpm = 60000.0 / (float)delta;
  if (bpm < 30.0 || bpm > 220.0)
    return;
  ppgStoreIBI((unsigned long)delta);
  stressPushIBI((unsigned long)delta);  // Feed IBI into stress model ibiWindow for HRV features
  uint8_t medBpm = ppgMedianBPM();
  if (medBpm >= 40 && medBpm <= 200) {
    if (ppgBpmEma < 0)
      ppgBpmEma = (float)medBpm;
    else
      ppgBpmEma = PPG_BPM_EMA_ALPHA * (float)medBpm +
                  (1.0 - PPG_BPM_EMA_ALPHA) * ppgBpmEma;
    // HR regression calibration disabled — inaccurate results on validation
    currentHeartRate = (uint8_t)constrain((int)(ppgBpmEma + 0.5), 40, 200);
    heartRateValid = true;
    hrStatus = SENSOR_OK;
    hrBpmHistory[hrBpmHistoryIndex] = currentHeartRate;
    hrBpmHistoryIndex = (hrBpmHistoryIndex + 1) % HR_BPM_HISTORY_SIZE;
    if (hrBpmHistoryIndex == 0)
      hrBpmHistoryFull = true;
  }
}

void sampleHeartRate() {
  // Auto-recover: retry init if sensor failed at startup (e.g. I2C stuck after reflash).
  // Only attempt once every 5 seconds to avoid flooding the I2C bus.
  if (!max30102Found) {
    static unsigned long _lastHrRetry = 0;
    unsigned long _nowR = millis();
    if (_nowR - _lastHrRetry >= 5000) {
      _lastHrRetry = _nowR;
      if (max30102.begin(Wire, I2C_SPEED_STANDARD)) {
        max30102Found = true;
        max30102.setup(MAX30102_LED_BRIGHTNESS, MAX30102_SAMPLE_AVG,
                       MAX30102_LED_MODE, MAX30102_SAMPLE_RATE,
                       MAX30102_PULSE_WIDTH, MAX30102_ADC_RANGE);
        max30102.setPulseAmplitudeRed(0xFF);
        max30102.setPulseAmplitudeIR(0xFF);
        max30102.setPulseAmplitudeGreen(0);
        hrStatus = SENSOR_WAITING;
        Serial.println(F("[HR] MAX30102 recovered on retry"));
      }
    }
    if (!max30102Found) {
      hrStatus = SENSOR_INIT_FAIL;
      return;
    }
  }
  long irValue = max30102.getIR();
  long redValue = max30102.getRed();
  unsigned long nowMs = millis();
  ppgIrRaw = (uint32_t)irValue;
  ppgRedRaw = (uint32_t)redValue;
  ppgRawLatest = (int)(irValue >> 4);
  hrRawBuffer[hrBufferIndex] = ppgRawLatest;
  hrBufferIndex = (hrBufferIndex + 1) % HR_RAW_BUFFER_SIZE;
  if (hrBufferIndex == 0)
    hrBufferFull = true;
  ppgDcRemoved = ppgHighPass(ppgRawLatest);
  float lp1Out = ppgLowPass1(ppgDcRemoved);
  ppgFiltered = ppgLowPass2(lp1Out);
  ppgMaOutput = ppgMovingAvg(ppgFiltered);
  hrSignalQuality = computeHRSignalQuality();
  ppgDisplayUpdate(ppgMaOutput);
  ppgBeatMarker = false;

  // ---- Skin-aware wrist detection (v4.1.1) ----
  // Step 1: IR proximity check (is anything near the sensor?)
  if (irValue < (long)MAX30102_IR_WRIST_THRESH) {
    // Nothing near sensor — clear everything
    wristLowCount++;
    skinConfirmCount = 0;
    skinRejectCount = 0;
    skinConfirmed = false;
    ppgRedIrRatioInit = false;
    if (wristLowCount >= MAX30102_WRIST_LOST_COUNT && deviceWorn) {
      deviceWorn = false;
      heartRateValid = false;
      currentHeartRate = 0;
      hrBpmHistoryIndex = 0;
      hrBpmHistoryFull = false;
      ppgIbiIndex = 0;
      ppgIbiCount = 0;
      hrStatus = SENSOR_WAITING;
      lastAcceptedBeatTime = 0;
      lastBeatTime = 0;
      lastCustomPipelineBeatTime = 0;
      ppgBpmEma = -1.0;
    }
  } else {
    wristLowCount = 0;

    // Step 2: Red/IR ratio check — discriminate skin from objects
    // Skin hemoglobin absorbs RED >> IR → ratio 0.2-0.85
    // Objects reflect both similarly → ratio ~0.9-1.1
    if (irValue > 500) {
      float ratio = (float)redValue / (float)irValue;
      if (!ppgRedIrRatioInit) {
        ppgRedIrRatioEma = ratio;
        ppgRedIrRatioInit = true;
      } else {
        ppgRedIrRatioEma = 0.05f * ratio + 0.95f * ppgRedIrRatioEma;
      }

      bool ratioIsSkin = (ppgRedIrRatioEma >= SKIN_RATIO_MIN &&
                          ppgRedIrRatioEma <= SKIN_RATIO_MAX);

      if (ratioIsSkin) {
        skinRejectCount = 0;
        if (!skinConfirmed) {
          skinConfirmCount++;
          if (skinConfirmCount >= SKIN_CONFIRM_SAMPLES) {
            skinConfirmed = true;
          }
        }
      } else {
        skinConfirmCount = 0;
        if (skinConfirmed) {
          skinRejectCount++;
          if (skinRejectCount >= SKIN_REJECT_SAMPLES) {
            skinConfirmed = false;
          }
        }
      }
    }

    // Step 3: Update worn status based on confirmed skin contact
    if (skinConfirmed && !deviceWorn) {
      deviceWorn = true;
      heartRateValid = false;
      currentHeartRate = 0;
      hrBpmHistoryIndex = 0;
      hrBpmHistoryFull = false;
      ppgIbiIndex = 0;
      ppgIbiCount = 0;
      hrStatus = SENSOR_WAITING;
      lastAcceptedBeatTime = 0;
      lastBeatTime = 0;
      lastCustomPipelineBeatTime = 0;
      ppgBpmEma = -1.0;
      ppgHpInit = false;
      ppgLp1Init = false;
      ppgLp2Init = false;
      ppgMaFull = false;
      ppgMaIdx = 0;
      ppgRunningMin = 9999.0;
      ppgRunningMax = -9999.0;
      ppgAdaptCounter = 0;
      ppgAboveThreshold = false;
      ppgWarmupCount = 0;
      ppgPrevFilteredInit = false;
      ppgSlopeSmoothed = 0.0f;
      ppgSlopePrev = 0.0f;
      ppgLastPeakTime = 0;
      ppgDispMin = 9999.0;
      ppgDispMax = -9999.0;
      ppgDispMinHold = 0.0;
      ppgDispMaxHold = 1.0;
      ppgDispCounter = 0;
      Serial.println(F("[PPG] Skin contact confirmed — wrist detected"));
    } else if (!skinConfirmed && deviceWorn) {
      deviceWorn = false;
      heartRateValid = false;
      currentHeartRate = 0;
      hrBpmHistoryIndex = 0;
      hrBpmHistoryFull = false;
      ppgIbiIndex = 0;
      ppgIbiCount = 0;
      hrStatus = SENSOR_WAITING;
      lastAcceptedBeatTime = 0;
      lastBeatTime = 0;
      lastCustomPipelineBeatTime = 0;
      ppgBpmEma = -1.0;
      Serial.println(F("[PPG] Skin contact lost — not worn"));
    }
  }
  if (plotterMode)
    outputPlotterLine();
  if (!deviceWorn) {
    heartRateValid = false;
    currentHeartRate = 0;
    hrStatus = SENSOR_WAITING;
    return;
  }

  bool motionSafe = (fabs(accelMagnitude - 1.0) < PPG_MOTION_THRESH_G);
  unsigned long ppgIbi = ppgDetectPeak(ppgFiltered, nowMs);
  if (ppgIbi > 0 && motionSafe) {
    processBeat(ppgLastPeakTime);
    lastCustomPipelineBeatTime = nowMs;
    ppgBeatMarker = true;
  }
  long irScaled = irValue >> 1;  // Wrist: less shift to preserve weak signal (was >>2)
  if (checkForBeat(irScaled) && motionSafe) {
    if (lastCustomPipelineBeatTime == 0 ||
        (nowMs - lastCustomPipelineBeatTime) >= SPARKFUN_FALLBACK_TIMEOUT_MS) {
      processBeat(nowMs);
      ppgBeatMarker = true;
    }
  }
}

float computeHRSignalQuality() {
  if (!hrBufferFull && hrBufferIndex < 10)
    return 0.0;
  int count = hrBufferFull ? HR_RAW_BUFFER_SIZE : hrBufferIndex;
  int minVal = 4095, maxVal = 0;
  for (int i = 0; i < count; i++) {
    if (hrRawBuffer[i] < minVal)
      minVal = hrRawBuffer[i];
    if (hrRawBuffer[i] > maxVal)
      maxVal = hrRawBuffer[i];
  }
  return constrain((maxVal - minVal) / 200.0, 0.0, 1.0);
}

float computeHRStability() {
  int count = hrBpmHistoryFull ? HR_BPM_HISTORY_SIZE : hrBpmHistoryIndex;
  if (count < 3)
    return -1.0;
  float sum = 0, sumSq = 0;
  for (int i = 0; i < count; i++) {
    sum += hrBpmHistory[i];
    sumSq += (float)hrBpmHistory[i] * hrBpmHistory[i];
  }
  float mean = sum / count;
  float variance = (sumSq / count) - (mean * mean);
  if (variance < 0)
    variance = 0;
  return (mean > 0) ? (sqrt(variance) / mean) * 100.0 : 0.0;
}

// =====================================================================
//                          GSR FUNCTIONS
// =====================================================================
float gsrADCtoMicroSiemens(int adcRaw) {
  // Two-step pooled calibration — 10 subjects, 2429 valid points, R² = 0.7932
  // Step 1: ADC → Resistance (voltage divider, 10kΩ pull-up, 3.3V, 12-bit ADC)
  //   R = ((4095 + 2×ADC) × 10000) / (2275 − ADC)
  // Step 2: Resistance → Calc µS
  //   calc_uS = 1,000,000 / R
  // Step 3: Pooled OLS correction
  //   poly_uS = 0.3460 × calc_uS + 4.0800
  float denom = 2275.0f - (float)adcRaw;
  if (denom <= 0.0f) return 0.0f;   // ADC ≥ 2275 is outside sensor range
  float resistance = ((4095.0f + 2.0f * adcRaw) * 10000.0f) / denom;
  if (resistance <= 0.0f) return 0.0f;
  float calc_uS = 1000000.0f / resistance;
  float poly_uS = 0.3460f * calc_uS + 4.0800f;
  return (poly_uS < 0.0f) ? 0.0f : poly_uS;
}

void readGSR() {
  long sum = 0;
  for (int i = 0; i < GSR_SAMPLES_PER_READ; i++) {
    sum += analogRead(GSR_PIN);
    delayMicroseconds(100);
  }
  currentGSRRaw = sum / GSR_SAMPLES_PER_READ;
  if (currentGSRRaw > 0 && currentGSRRaw < 4095) {
    currentGSRVoltage = (currentGSRRaw / 4095.0) * 3.3;
    currentGSRResistance =
        ((3.3 - currentGSRVoltage) / currentGSRVoltage) * 1000000.0;
    if (currentGSRResistance < 0)
      currentGSRResistance = 0;
    currentGSRResistanceSmoothed =
        applyEMA(gsrEmaFiltered, currentGSRResistance, GSR_EMA_ALPHA);
    currentGSRMicroSiemens = gsrADCtoMicroSiemens(currentGSRRaw);
    gsrStatus = SENSOR_OK;
  } else {
    currentGSRVoltage = 0;
    currentGSRResistance = 0;
    gsrStatus = SENSOR_READ_ERROR;
  }
  gsrHistory[gsrHistoryIndex] = currentGSRResistanceSmoothed;
  gsrHistoryIndex = (gsrHistoryIndex + 1) % GSR_HISTORY_SIZE;
  if (gsrHistoryIndex == 0)
    gsrHistoryFull = true;
  gsrBaseline = computeGSRBaseline();

  // Feed EDA/GSR into stress model window (edge computing)
  if (gsrStatus == SENSOR_OK) {
    stressPushEDA(currentGSRMicroSiemens);
  }
}

float computeGSRBaseline() {
  int count = gsrHistoryFull ? GSR_HISTORY_SIZE : gsrHistoryIndex;
  if (count == 0)
    return 0.0;
  float sum = 0;
  for (int i = 0; i < count; i++)
    sum += gsrHistory[i];
  return sum / count;
}

// =====================================================================
//    MLX90614 FUNCTIONS (v3.8.3 — EEPROM emissivity + stable filter)
// =====================================================================

bool initMLX90614() {
  Wire.beginTransmission(MLX90614_ADDRESS);
  if (Wire.endTransmission() != 0)
    return false;
  delay(50);
  float testTemp = readMLX90614Temp(MLX90614_TOBJ1);
  return (testTemp >= -40.0 && testTemp <= 125.0);
}

float readMLX90614Temp(uint8_t reg) {
  Wire.beginTransmission(MLX90614_ADDRESS);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0)
    return -999.0;
  Wire.requestFrom((uint8_t)MLX90614_ADDRESS, (uint8_t)3);
  if (Wire.available() < 3)
    return -999.0;
  uint8_t lsb = Wire.read(), msb = Wire.read(), pec = Wire.read();
  uint16_t rawData = ((uint16_t)msb << 8) | lsb;
  if (rawData & 0x8000)
    return -999.0;
  return (rawData * 0.02) - 273.15;
}

void readMLX90614() {
  float objTemp = readMLX90614Temp(MLX90614_TOBJ1);
  float ambTemp = readMLX90614Temp(MLX90614_TA);

  if (objTemp != -999.0 && ambTemp != -999.0) {
    if (objTemp >= 20.0 && objTemp <= 45.0) {
      tempConsecutiveErrors = 0;
      currentTempAmbient = ambTemp;

      float ambCompensated = applyAmbientCompensation(objTemp, ambTemp);
      float medianVal = tempMedianFilter(ambCompensated);
      float calibrated = tempLinearCalibrate(medianVal);
      currentTempObject = calibrated;

      tempWarmupCount++;
      if (!tempEmaInit || tempWarmupCount <= MLX_WARMUP_SAMPLES) {
        tempEmaFast = calibrated;
        tempEmaSlow = calibrated;
        if (tempWarmupCount >= MLX_WARMUP_SAMPLES)
          tempEmaInit = true;
      } else {
        float delta = fabs(calibrated - tempEmaFast);
        if (delta <= MLX_OUTLIER_THRESHOLD) {
          tempEmaFast = MLX_EMA_FAST_ALPHA * calibrated +
                        (1.0f - MLX_EMA_FAST_ALPHA) * tempEmaFast;
          tempEmaSlow = MLX_EMA_SLOW_ALPHA * tempEmaFast +
                        (1.0f - MLX_EMA_SLOW_ALPHA) * tempEmaSlow;
        }
      }

      // Use fast EMA through rate limiter for display — tracks skin temp
      // changes quickly while still suppressing ADC noise spikes.
      float stableOutput = tempRateLimiter(tempEmaFast);
      currentTempCalibrated = stableOutput;
      tempStatus = SENSOR_OK;

      tempHistory[tempHistoryIndex] = medianVal;
      tempHistoryIndex = (tempHistoryIndex + 1) % TEMP_HISTORY_SIZE;
      if (tempHistoryIndex == 0)
        tempHistoryFull = true;
      tempStability = computeTempStability();

      // Feed calibrated skin temp into stress model window (edge computing)
      stressPushTemp(currentTempCalibrated);
    } else {
      tempConsecutiveErrors++;
      tempStatus = SENSOR_READ_ERROR;
    }
  } else {
    tempConsecutiveErrors++;
    tempStatus = SENSOR_READ_ERROR;
    if (tempConsecutiveErrors >= TEMP_MAX_ERRORS) {
      tempStatus = SENSOR_RECOVERING;
      tempConsecutiveErrors = 0;
    }
  }
}

float computeTempStability() {
  int count = tempHistoryFull ? TEMP_HISTORY_SIZE : tempHistoryIndex;
  if (count < 3)
    return -1.0;
  float sum = 0, sumSq = 0;
  for (int i = 0; i < count; i++) {
    sum += tempHistory[i];
    sumSq += tempHistory[i] * tempHistory[i];
  }
  float mean = sum / count;
  float variance = (sumSq / count) - (mean * mean);
  if (variance < 0)
    variance = 0;
  return sqrt(variance);
}

// =====================================================================
//    MPU6050 FUNCTIONS (v3.9 — DLPF + calibrated gyro/accel)
// =====================================================================
// CALIBRATION STRATEGY:
//   The MPU6050 has hardware offset registers for both gyro and accel.
//   - Gyro offsets (0x13-0x18): 16-bit signed, LSB matches raw output LSB.
//     Writing the negative of the measured bias here makes the hardware
//     subtract it before the data reaches output registers.
//     Reference: InvenSense "MPU Hardware Offset Registers" app note.
//   - Accel offsets (0x06-0x0B): Also 16-bit, BUT bit 0 of each low byte
//     is the temperature compensation enable flag. Writing without masking
//     this bit can disable factory TC calibration. To avoid this risk, we
//     use software subtraction for accelerometer offsets.
//
// DLPF CONFIGURATION:
//   Register 0x1A (CONFIG), bits [2:0] = DLPF_CFG.
//   DLPF_CFG=3: Accel BW=44Hz delay=4.9ms, Gyro BW=42Hz delay=4.8ms,
//               Fs=1kHz for both. Good balance of noise rejection and
//               latency for wearable motion detection at 5Hz readout.
//   Reference: MPU-6000/6050 Register Map Rev 4.2, Table on p.13.
//
// SAMPLE RATE:
//   Register 0x19 (SMPLRT_DIV). Sample Rate = 1kHz / (1 + SMPLRT_DIV).
//   SMPLRT_DIV=4 -> 200 Hz internal sample rate. Our firmware reads at
//   5 Hz (MPU_INTERVAL=200ms), so internal oversampling + DLPF provides
//   excellent noise averaging.
// =====================================================================

// Helper: write a single byte to an MPU6050 register
void mpuWriteByte(uint8_t reg, uint8_t val) {
  Wire.beginTransmission(MPU6050_ADDRESS);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission();
}

// Helper: read a single byte from an MPU6050 register
uint8_t mpuReadByte(uint8_t reg) {
  Wire.beginTransmission(MPU6050_ADDRESS);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom((uint8_t)MPU6050_ADDRESS, (uint8_t)1);
  if (Wire.available())
    return Wire.read();
  return 0;
}

// Helper: write 16-bit signed value to two consecutive registers (H, L)
void mpuWriteWord(uint8_t regH, int16_t val) {
  Wire.beginTransmission(MPU6050_ADDRESS);
  Wire.write(regH);
  Wire.write((uint8_t)((val >> 8) & 0xFF)); // High byte
  Wire.write((uint8_t)(val & 0xFF));        // Low byte
  Wire.endTransmission();
}

bool initMPU6050() {
  Wire.beginTransmission(MPU6050_ADDRESS);
  Wire.write(MPU6050_WHO_AM_I);
  if (Wire.endTransmission(false) != 0)
    return false;
  Wire.requestFrom((uint8_t)MPU6050_ADDRESS, (uint8_t)1);
  if (!Wire.available())
    return false;
  uint8_t whoAmI = Wire.read();
  if (whoAmI != 0x68 && whoAmI != 0x72 && whoAmI != 0x98)
    return false;

  // Reset the device for a clean state
  mpuWriteByte(MPU6050_PWR_MGMT_1, 0x80); // Set bit 7 = device reset
  delay(100);                             // Wait for reset to complete

  // Wake up, select PLL with X-axis gyro as clock source (more stable
  // than internal 8MHz oscillator). Register Map Section 4.28.
  mpuWriteByte(MPU6050_PWR_MGMT_1, 0x01); // CLKSEL=1 (PLL with X gyro)
  delay(10);

  // Configure DLPF: DLPF_CFG=3 → Accel BW 44Hz, Gyro BW 42Hz, Fs=1kHz
  // This significantly reduces high-frequency noise from vibrations,
  // wrist tremor, and I2C EMI. For our 5 Hz readout, latency of ~5ms
  // is negligible.
  // Register Map Section 4.3:
  //   DLPF_CFG | Accel BW | Gyro BW | Fs
  //   0        | 260 Hz   | 256 Hz  | 8 kHz  (no filtering)
  //   1        | 184 Hz   | 188 Hz  | 1 kHz
  //   2        | 94 Hz    | 98 Hz   | 1 kHz
  //   3        | 44 Hz    | 42 Hz   | 1 kHz  <-- selected
  //   4        | 21 Hz    | 20 Hz   | 1 kHz
  //   5        | 10 Hz    | 10 Hz   | 1 kHz
  //   6        | 5 Hz     | 5 Hz    | 1 kHz
  mpuWriteByte(MPU6050_CONFIG, 0x03); // DLPF_CFG = 3
  Serial.println(F("[IMU]  DLPF enabled: Accel BW=44Hz, Gyro BW=42Hz"));

  // Sample rate divider: Fs=1kHz / (1+4) = 200 Hz internal rate
  mpuWriteByte(MPU6050_SMPLRT_DIV, 0x04);
  Serial.println(F("[IMU]  Sample rate: 200 Hz (SMPLRT_DIV=4)"));

  // Accelerometer: ±2g (most sensitive, 16384 LSB/g)
  // Best resolution for detecting subtle wrist motion and orientation.
  mpuWriteByte(MPU6050_ACCEL_CONFIG, 0x00); // AFS_SEL=0 → ±2g

  // Gyroscope: ±250 dps (most sensitive, 131 LSB/dps)
  // Wrist angular velocity during normal wear is well within ±250 dps.
  mpuWriteByte(MPU6050_GYRO_CONFIG, 0x00); // FS_SEL=0 → ±250 dps

  delay(50);
  return true;
}

// =====================================================================
//   MPU6050 CALIBRATION ROUTINE
// =====================================================================
// Procedure (per InvenSense app note + community best practice):
//   1. Device must be stationary on a flat surface, Z-axis pointing UP.
//   2. Discard first MPU_CAL_DISCARD samples (DLPF settling time).
//   3. Collect MPU_CAL_SAMPLES raw readings from all 6 axes.
//   4. Compute mean for each axis.
//   5. Gyro bias = mean (target is 0 for all axes at rest).
//      Write negative of bias to hardware offset registers 0x13-0x18.
//   6. Accel bias = mean - expected (expected: X=0, Y=0, Z=+16384).
//      Store as software offset; subtract in readMPU6050().
//   7. Print all offsets for verification.
//
// NOTE: Each MPU6050 unit has different offsets due to manufacturing
// variation. Re-calibration is needed if the sensor is remounted or
// if operating temperature changes significantly.
// =====================================================================
void calibrateMPU6050() {
  if (mpuStatus == SENSOR_INIT_FAIL) {
    Serial.println(F("[IMU]  Cannot calibrate — sensor not found"));
    return;
  }

  // Clear any existing hardware gyro offsets before calibrating,
  // so we measure the true raw bias.
  mpuWriteWord(MPU6050_XG_OFFS_USRH, 0);
  mpuWriteWord(MPU6050_YG_OFFS_USRH, 0);
  mpuWriteWord(MPU6050_ZG_OFFS_USRH, 0);
  delay(10);

  // Accumulators (use int32_t to avoid overflow: 500 * 16384 = 8.19M, fits)
  int32_t sumAx = 0, sumAy = 0, sumAz = 0;
  int32_t sumGx = 0, sumGy = 0, sumGz = 0;

  // Discard initial samples to let DLPF settle
  Serial.print(F("[IMU]  Discarding "));
  Serial.print(MPU_CAL_DISCARD);
  Serial.println(F(" samples (DLPF settling)..."));
  for (int i = 0; i < MPU_CAL_DISCARD; i++) {
    Wire.beginTransmission(MPU6050_ADDRESS);
    Wire.write(MPU6050_ACCEL_XOUT_H);
    Wire.endTransmission(false);
    Wire.requestFrom((uint8_t)MPU6050_ADDRESS, (uint8_t)14, (uint8_t)true);
    // Read and discard
    for (int b = 0; b < 14 && Wire.available(); b++)
      Wire.read();
    delay(6); // 6ms > 5ms sample period (200Hz internal rate) — guarantees fresh data
  }

  // Collect calibration samples
  Serial.print(F("[IMU]  Collecting "));
  Serial.print(MPU_CAL_SAMPLES);
  Serial.println(F(" samples..."));

  // Pass 1: collect all samples at 200 Hz (one new sample per 5ms; we wait 6ms)
  // Accel at ±2g: outlier gate ±0.5g = ±8192 LSB from expected rest value
  // Gyro  at ±250dps: outlier gate ±2dps = ±262 LSB (Ferraris et al., 1995)
  const int32_t ACCEL_XY_GATE = 8192;  // 0.5g max deviation from 0
  const int32_t ACCEL_Z_GATE  = 8192;  // 0.5g max deviation from 16384
  const int32_t GYRO_GATE     = 262;   // 2 dps max deviation from 0

  int validSamples = 0;
  int rejectedSamples = 0;
  for (int i = 0; i < MPU_CAL_SAMPLES; i++) {
    Wire.beginTransmission(MPU6050_ADDRESS);
    Wire.write(MPU6050_ACCEL_XOUT_H);
    if (Wire.endTransmission(false) != 0) {
      delay(6);
      continue;
    }
    Wire.requestFrom((uint8_t)MPU6050_ADDRESS, (uint8_t)14, (uint8_t)true);
    if (Wire.available() < 14) {
      delay(6);
      continue;
    }

    int16_t rawAx = (Wire.read() << 8) | Wire.read();
    int16_t rawAy = (Wire.read() << 8) | Wire.read();
    int16_t rawAz = (Wire.read() << 8) | Wire.read();
    int16_t rawTemp = (Wire.read() << 8) | Wire.read();
    (void)rawTemp;
    int16_t rawGx = (Wire.read() << 8) | Wire.read();
    int16_t rawGy = (Wire.read() << 8) | Wire.read();
    int16_t rawGz = (Wire.read() << 8) | Wire.read();

    // Outlier rejection — discard samples that imply movement during calibration
    // (Ferraris et al., 1995; Tedaldi et al., 2014)
    if (abs((int32_t)rawAx) > ACCEL_XY_GATE ||
        abs((int32_t)rawAy) > ACCEL_XY_GATE ||
        abs((int32_t)rawAz - 16384) > ACCEL_Z_GATE ||
        abs((int32_t)rawGx) > GYRO_GATE ||
        abs((int32_t)rawGy) > GYRO_GATE ||
        abs((int32_t)rawGz) > GYRO_GATE) {
      rejectedSamples++;
      delay(6);
      continue;
    }

    sumAx += rawAx;
    sumAy += rawAy;
    sumAz += rawAz;
    sumGx += rawGx;
    sumGy += rawGy;
    sumGz += rawGz;
    validSamples++;

    delay(6); // 6ms > 5ms sample period — each read gets a fresh ADC value
  }

  Serial.print(F("[IMU]  Samples accepted: "));
  Serial.print(validSamples);
  Serial.print(F("  rejected (motion): "));
  Serial.println(rejectedSamples);

  if (validSamples < 200) {
    Serial.println(F("[IMU]  WARNING: <200 valid samples — device may have moved during calibration."));
    Serial.println(F("[IMU]  Send 'i' to recalibrate with device flat and still."));
    if (validSamples == 0) return; // cannot compute mean — abort
  }

  // Compute mean bias (raw ADC units)
  int16_t meanAx = (int16_t)(sumAx / validSamples);
  int16_t meanAy = (int16_t)(sumAy / validSamples);
  int16_t meanAz = (int16_t)(sumAz / validSamples);
  int16_t meanGx = (int16_t)(sumGx / validSamples);
  int16_t meanGy = (int16_t)(sumGy / validSamples);
  int16_t meanGz = (int16_t)(sumGz / validSamples);

  // === GYROSCOPE: Write hardware offset registers ===
  // Target at rest: 0, 0, 0 (no rotation)
  // The hardware subtracts the offset register value from each raw sample.
  // So we write the measured bias directly (positive bias → positive offset
  // → hardware subtracts it → output becomes ~0).
  // Per InvenSense app note: offset = -bias for the gyro registers
  // Actually, testing shows the registers ADD to the output, so to cancel
  // a positive bias, we write the NEGATIVE:
  mpuGyroOffsetX = -meanGx;
  mpuGyroOffsetY = -meanGy;
  mpuGyroOffsetZ = -meanGz;

  mpuWriteWord(MPU6050_XG_OFFS_USRH, mpuGyroOffsetX);
  mpuWriteWord(MPU6050_YG_OFFS_USRH, mpuGyroOffsetY);
  mpuWriteWord(MPU6050_ZG_OFFS_USRH, mpuGyroOffsetZ);

  // === ACCELEROMETER: Software offsets ===
  // Target at rest (flat, Z-up): X=0, Y=0, Z=+16384 (1g at ±2g range)
  // Offset = measured_mean - expected
  mpuAccelOffsetX = meanAx;         // expected 0 → offset = mean - 0
  mpuAccelOffsetY = meanAy;         // expected 0 → offset = mean - 0
  mpuAccelOffsetZ = meanAz - 16384; // expected +16384 → offset = mean - 16384

  mpuCalibrated = true;

  // Print results
  Serial.println(F("[IMU]  Calibration complete!"));
  Serial.print(F("[IMU]  Samples used: "));
  Serial.println(validSamples);
  Serial.println(F("[IMU]  --- Raw mean (ADC units) ---"));
  Serial.print(F("[IMU]    Accel: X="));
  Serial.print(meanAx);
  Serial.print(F(" Y="));
  Serial.print(meanAy);
  Serial.print(F(" Z="));
  Serial.println(meanAz);
  Serial.print(F("[IMU]    Gyro:  X="));
  Serial.print(meanGx);
  Serial.print(F(" Y="));
  Serial.print(meanGy);
  Serial.print(F(" Z="));
  Serial.println(meanGz);
  Serial.println(F("[IMU]  --- Applied offsets ---"));
  Serial.print(F("[IMU]    Gyro HW:  X="));
  Serial.print(mpuGyroOffsetX);
  Serial.print(F(" Y="));
  Serial.print(mpuGyroOffsetY);
  Serial.print(F(" Z="));
  Serial.println(mpuGyroOffsetZ);
  Serial.print(F("[IMU]    Accel SW: X="));
  Serial.print(mpuAccelOffsetX);
  Serial.print(F(" Y="));
  Serial.print(mpuAccelOffsetY);
  Serial.print(F(" Z="));
  Serial.println(mpuAccelOffsetZ);

  // Convert to physical units for readability
  Serial.println(F("[IMU]  --- Bias in physical units ---"));
  Serial.print(F("[IMU]    Accel bias: X="));
  Serial.print(meanAx / 16384.0, 4);
  Serial.print(F("g Y="));
  Serial.print(meanAy / 16384.0, 4);
  Serial.print(F("g Z="));
  Serial.print((meanAz - 16384) / 16384.0, 4);
  Serial.println(F("g"));
  Serial.print(F("[IMU]    Gyro bias:  X="));
  Serial.print(meanGx / 131.0, 2);
  Serial.print(F(" Y="));
  Serial.print(meanGy / 131.0, 2);
  Serial.print(F(" Z="));
  Serial.print(meanGz / 131.0, 2);
  Serial.println(F(" dps"));

  // Verify by reading a few samples with offsets applied
  delay(50);
  Serial.println(F("[IMU]  --- Verification (5 post-cal readings) ---"));
  for (int v = 0; v < 5; v++) {
    Wire.beginTransmission(MPU6050_ADDRESS);
    Wire.write(MPU6050_ACCEL_XOUT_H);
    Wire.endTransmission(false);
    Wire.requestFrom((uint8_t)MPU6050_ADDRESS, (uint8_t)14, (uint8_t)true);
    if (Wire.available() >= 14) {
      int16_t rax = (Wire.read() << 8) | Wire.read();
      int16_t ray = (Wire.read() << 8) | Wire.read();
      int16_t raz = (Wire.read() << 8) | Wire.read();
      int16_t rtemp = (Wire.read() << 8) | Wire.read();
      (void)rtemp;
      int16_t rgx = (Wire.read() << 8) | Wire.read();
      int16_t rgy = (Wire.read() << 8) | Wire.read();
      int16_t rgz = (Wire.read() << 8) | Wire.read();
      // Apply software accel offsets
      float ax = (rax - mpuAccelOffsetX) / 16384.0;
      float ay = (ray - mpuAccelOffsetY) / 16384.0;
      float az = (raz - mpuAccelOffsetZ) / 16384.0;
      // Gyro offsets already applied by hardware
      float gx = rgx / 131.0;
      float gy = rgy / 131.0;
      float gz = rgz / 131.0;
      Serial.print(F("[IMU]    A("));
      Serial.print(ax, 3);
      Serial.print(F(","));
      Serial.print(ay, 3);
      Serial.print(F(","));
      Serial.print(az, 3);
      Serial.print(F(")g  G("));
      Serial.print(gx, 2);
      Serial.print(F(","));
      Serial.print(gy, 2);
      Serial.print(F(","));
      Serial.print(gz, 2);
      Serial.println(F(")dps"));
    }
    delay(20);
  }
  Serial.println(F("[IMU]  Expected: A(~0, ~0, ~1.00)g  G(~0, ~0, ~0)dps"));
}

// =====================================================================
//   MPU6050 READ (with calibration offsets applied)
// =====================================================================
void readMPU6050() {
  Wire.beginTransmission(MPU6050_ADDRESS);
  Wire.write(MPU6050_ACCEL_XOUT_H);
  if (Wire.endTransmission(false) != 0) {
    mpuStatus = SENSOR_READ_ERROR;
    return;
  }
  Wire.requestFrom((uint8_t)MPU6050_ADDRESS, (uint8_t)14, (uint8_t)true);
  if (Wire.available() < 14) {
    mpuStatus = SENSOR_READ_ERROR;
    return;
  }

  int16_t rawAx = (Wire.read() << 8) | Wire.read();
  int16_t rawAy = (Wire.read() << 8) | Wire.read();
  int16_t rawAz = (Wire.read() << 8) | Wire.read();
  int16_t rawTemp = (Wire.read() << 8) | Wire.read();
  int16_t rawGx = (Wire.read() << 8) | Wire.read();
  int16_t rawGy = (Wire.read() << 8) | Wire.read();
  int16_t rawGz = (Wire.read() << 8) | Wire.read();

  // Apply software accelerometer calibration offsets
  // (Gyro offsets are already applied by hardware registers)
  if (mpuCalibrated) {
    accelX = (rawAx - mpuAccelOffsetX) / 16384.0;
    accelY = (rawAy - mpuAccelOffsetY) / 16384.0;
    accelZ = (rawAz - mpuAccelOffsetZ) / 16384.0;
  } else {
    // Fallback: no calibration applied
    accelX = rawAx / 16384.0;
    accelY = rawAy / 16384.0;
    accelZ = rawAz / 16384.0;
  }

  // Gyro: hardware offsets are already subtracted by the MPU6050
  gyroX = rawGx / 131.0;
  gyroY = rawGy / 131.0;
  gyroZ = rawGz / 131.0;

  mpuTemperature = (rawTemp / 340.0) + 36.53;
  accelMagnitude = sqrt(accelX * accelX + accelY * accelY + accelZ * accelZ);
  mpuStatus = SENSOR_OK;

  // Feed acc data into stress model window (edge computing)
  stressPushAcc(accelX, accelY, accelZ, accelMagnitude);
}

// =====================================================================
//                       BATTERY FUNCTIONS
// =====================================================================
void readBattery() {
  long sum = 0;
  for (int i = 0; i < 10; i++) {
    sum += analogRead(VBAT_PIN);
    delayMicroseconds(100);
  }
  int adcRaw = sum / 10;
  float adcVoltage = (adcRaw / 4095.0) * 3.3;
  batteryVoltage = adcVoltage * VBAT_DIVIDER_RATIO;

  // Always compute and send battery percent — no sentinel.
  // If GPIO32 has no voltage divider, batteryVoltage will read ~0 and
  // batteryPercent will clamp to 0, which is visible in the app.
  // This allows field-testing on LiPo-only power without USB/Serial.
  batteryVoltageSmoothed =
      applyEMA(batEmaFiltered, batteryVoltage, BAT_EMA_ALPHA);
  batteryPercent = constrain(
      (int)(((batteryVoltageSmoothed - VBAT_EMPTY) / (VBAT_FULL - VBAT_EMPTY)) *
            100.0),
      0, 100);
}

void updateBatteryLED() {
  if (batteryPercent > 60)
    setRGBColor(0, 255, 0);
  else if (batteryPercent > 30)
    setRGBColor(255, 255, 0);
  else if (batteryPercent > 10)
    setRGBColor(255, 0, 0);
  else {
    static bool b = false;
    b = !b;
    setRGBColor(b ? 255 : 0, 0, 0);
  }
}

void setRGBColor(uint8_t r, uint8_t g, uint8_t b) {
  analogWrite(RGB_RED_PIN, r);
  analogWrite(RGB_GREEN_PIN, g);
  analogWrite(RGB_BLUE_PIN, b);
}

// =====================================================================
//                       SERIAL COMMAND HANDLER
// =====================================================================
void handleSerialCommands() {
  if (Serial.available() <= 0)
    return;
  String input = Serial.readStringUntil('\n');
  input.trim();
  if (input.length() == 0)
    return;
  char cmd = input.charAt(0);

  switch (cmd) {
  case 'c':
  case 'C':
    tempFineTuneOffset = input.substring(1).toFloat();
    Serial.print(F("[CMD] Temp fine-tune offset: "));
    Serial.print(tempFineTuneOffset, 2);
    Serial.println(F(" C"));
    break;

  case 'e':
  case 'E': {
    float newEmiss = input.substring(1).toFloat();
    if (newEmiss >= 0.10 && newEmiss <= 1.00) {
      Serial.print(F("[CMD] Setting emissivity to "));
      Serial.println(newEmiss, 3);
      if (setMLX90614Emissivity(newEmiss)) {
        skinEmissivity = newEmiss;
        Serial.println(
            F("[CMD] Emissivity updated. Power-cycle sensor for full effect."));
      } else {
        Serial.println(F("[CMD] Emissivity write FAILED"));
      }
    } else {
      Serial.println(F("[CMD] Emissivity must be 0.10-1.00 (e.g. e0.95)"));
    }
    break;
  }

  case 'i':
  case 'I':
    Serial.println(F("[CMD] Re-running MPU6050 calibration..."));
    Serial.println(F("[CMD] KEEP DEVICE FLAT AND STILL!"));
    delay(1000); // Give user a moment to set device down
    calibrateMPU6050();
    break;

  case 'b':
  case 'B':
    Serial.println(F("[CMD] Resetting stress baseline calibration..."));
    Serial.println(F("[CMD] Keep device worn and stay calm for 5 minutes."));
    stressModelInit();
    break;

  case 's':
  case 'S':
    printSystemStatus();
    break;

  case 'h':
  case 'H':
    Serial.println(F("[CMD] Available commands:"));
    Serial.println(
        F("  c<value>  - Temp fine-tune offset (e.g. c0.3 or c-0.5)"));
    Serial.println(
        F("  e<value>  - Write emissivity to MLX90614 EEPROM (e.g. e0.95)"));
    Serial.println(
        F("  i         - Re-calibrate MPU6050 (keep device flat & still)"));
    Serial.println(
        F("  b         - Reset stress baseline (keep calm for 5 min)"));
    Serial.println(F("  s         - System status"));
    Serial.println(F("  p         - Toggle plotter mode"));
    Serial.println(F("  d         - Toggle CSV stream"));
    Serial.println(F("  h         - This help"));
    break;

  case 'p':
  case 'P':
    plotterMode = !plotterMode;
    csvStreamMode = false;
    Serial.println(plotterMode ? F("[CMD] Plotter ON")
                               : F("[CMD] Plotter OFF"));
    break;

  case 'd':
  case 'D':
    csvStreamMode = !csvStreamMode;
    plotterMode = false;
    if (csvStreamMode) {
      Serial.println(F("[CMD] CSV ON"));
      Serial.println(CSV_HEADER);
    } else
      Serial.println(F("[CMD] CSV OFF"));
    break;

  default:
    Serial.print(F("[CMD] Unknown: "));
    Serial.println(input);
    break;
  }
}

// =====================================================================
//                       DATA OUTPUT FUNCTIONS
// =====================================================================
const char *statusToString(SensorStatus s) {
  switch (s) {
  case SENSOR_OK:
    return "OK";
  case SENSOR_INIT_FAIL:
    return "INIT_FAIL";
  case SENSOR_READ_ERROR:
    return "READ_ERR";
  case SENSOR_RECOVERING:
    return "RECOVERING";
  case SENSOR_WAITING:
    return "WAITING";
  default:
    return "UNKNOWN";
  }
}

void outputDataPacket() {
  packetCount++;
  unsigned long uptimeMs = millis() - systemStartTime;
  unsigned long uptimeSec = uptimeMs / 1000;
  unsigned long hours = uptimeSec / 3600;
  unsigned long minutes = (uptimeSec % 3600) / 60;
  unsigned long seconds = uptimeSec % 60;
  float hrStability = computeHRStability();

  Serial.println(
      F("================================================================"));
  Serial.print(F("  PACKET #"));
  Serial.print(packetCount);
  Serial.print(F("  |  Uptime: "));
  if (hours < 10)
    Serial.print('0');
  Serial.print(hours);
  Serial.print(':');
  if (minutes < 10)
    Serial.print('0');
  Serial.print(minutes);
  Serial.print(':');
  if (seconds < 10)
    Serial.print('0');
  Serial.print(seconds);
  Serial.print(F("  |  millis: "));
  Serial.print(millis());
  Serial.println();
  Serial.println(
      F("----------------------------------------------------------------"));

  Serial.print(F("  [WEAR] Device Worn: "));
  Serial.println(deviceWorn ? F("YES") : F("NO"));
  Serial.println(
      F("  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"));

  // HR
  Serial.print(F("  [HR]   BPM: "));
  if (deviceWorn && heartRateValid && currentHeartRate > 0) {
    Serial.print(currentHeartRate);
    Serial.print(F("  | SQI: "));
    Serial.print(hrSignalQuality, 2);
    Serial.print(F("  | IBI: "));
    Serial.print(ppgIbiCount);
    Serial.print(F("/"));
    Serial.print(PPG_IBI_HISTORY);
    Serial.print(F("  | Status: "));
    Serial.println(statusToString(hrStatus));
  } else if (!deviceWorn) {
    Serial.print(F("---  | Raw: "));
    Serial.print(ppgRawLatest);
    Serial.println(F("  | NOT WORN"));
  } else {
    Serial.print(F("---  | IBI: "));
    Serial.print(ppgIbiCount);
    Serial.print(F("/"));
    Serial.print(PPG_IBI_HISTORY);
    Serial.print(F("  | "));
    Serial.println(statusToString(hrStatus));
  }
  Serial.println(
      F("  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"));

  // GSR
  Serial.print(F("  [GSR]  Raw: "));
  Serial.print(currentGSRRaw);
  Serial.print(F("  | "));
  Serial.print(currentGSRVoltage, 3);
  Serial.print(F("V"));
  Serial.print(F("  | Cal: "));
  Serial.print(currentGSRMicroSiemens, 2);
  Serial.print(F(" uS  | "));
  Serial.println(statusToString(gsrStatus));
  Serial.println(
      F("  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"));

  // TEMP
  Serial.print(F("  [TEMP] "));
  if (currentTempObject != -999.0) {
    Serial.print(F("Skin: "));
    Serial.print(currentTempObject, 2);
    Serial.print(F("C  | Stable: "));
    Serial.print(currentTempCalibrated, 2);
    Serial.print(F("C  | Amb: "));
    Serial.print(currentTempAmbient, 2);
    Serial.println(F("C"));
    Serial.print(F("         Emiss: "));
    Serial.print(skinEmissivity, 2);
    Serial.print(F("(EEPROM)  | Stab: "));
    if (tempStability >= 0) {
      Serial.print(tempStability, 4);
      Serial.print(F("C"));
      if (tempStability < 0.05)
        Serial.print(F(" (Stable)"));
      else if (tempStability < 0.2)
        Serial.print(F(" (Settling)"));
      else
        Serial.print(F(" (Fluctuating)"));
    } else
      Serial.print(F("N/A"));
    Serial.print(F("  | "));
    Serial.println(statusToString(tempStatus));
  } else {
    Serial.print(F("No reading  | "));
    Serial.println(statusToString(tempStatus));
  }
  Serial.println(
      F("  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"));

  // IMU (now shows calibration status)
  Serial.print(F("  [IMU]  Accel: X="));
  Serial.print(accelX, 3);
  Serial.print(F(" Y="));
  Serial.print(accelY, 3);
  Serial.print(F(" Z="));
  Serial.print(accelZ, 3);
  Serial.print(F("  |Mag|="));
  Serial.print(accelMagnitude, 3);
  Serial.print(F("g"));
  Serial.print(F("  | "));
  Serial.print(statusToString(mpuStatus));
  Serial.print(mpuCalibrated ? F(" [CAL]") : F(" [UNCAL]"));
  Serial.println();
  Serial.print(F("         Gyro:  X="));
  Serial.print(gyroX, 2);
  Serial.print(F(" Y="));
  Serial.print(gyroY, 2);
  Serial.print(F(" Z="));
  Serial.print(gyroZ, 2);
  Serial.println(F(" dps"));
  Serial.println(
      F("  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"));

  // BAT
  Serial.print(F("  [BAT]  "));
  Serial.print(batteryVoltageSmoothed, 2);
  Serial.print(F("V  | "));
  Serial.print(batteryPercent);
  Serial.println(F("%"));
  Serial.println(
      F("  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"));

  // STRESS (v4.1 — edge feature extraction + client classification)
  Serial.print(F("  [STRESS] "));
  if (!baseline.calibrated) {
    Serial.print(F("Calibrating baseline... "));
    Serial.print(baseline.samplesCollected);
    Serial.print(F("/"));
    Serial.println(BASELINE_SAMPLES_EDA);
  } else if (currentStress.stressIndex >= 0.0f) {
    Serial.print(F("Edge: "));
    Serial.print(currentStress.stressIndex, 1);
    Serial.print(F("/100  | "));
    Serial.print(stressCategoryLabel(currentStress.stressCategory));
    Serial.print(F("  | Features -> BLE -> App"));
    if (currentStress.motionArtifact)
      Serial.print(F("  [MOTION]"));
    Serial.println();

    HRVMetrics hrvDisp = computeHRV(&ibiWindow);
    if (hrvDisp.valid) {
      Serial.print(F("         HRV: RMSSD="));
      Serial.print(hrvDisp.rmssd, 1);
      Serial.print(F("ms  SDNN="));
      Serial.print(hrvDisp.sdnn, 1);
      Serial.print(F("ms  pNN50="));
      Serial.print(hrvDisp.pnn50, 1);
      Serial.println(F("%"));
    }
  } else {
    Serial.println(F("Waiting for data..."));
  }
  Serial.println(
      F("  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"));

  // BLE
  Serial.print(F("  [BLE]  "));
  Serial.println(bleDeviceConnected ? F("Connected") : F("Advertising"));

  Serial.println(
      F("================================================================\n"));
}

void printSystemStatus() {
  unsigned long uptimeSec = (millis() - systemStartTime) / 1000;
  Serial.println(F("\n======== SYSTEM STATUS v4.0 ========"));
  Serial.print(F("Uptime: "));
  Serial.print(uptimeSec);
  Serial.println(F("s"));
  Serial.print(F("Heap: "));
  Serial.print(ESP.getFreeHeap());
  Serial.println(F(" bytes"));

  Serial.println(F("\nSensors:"));
  Serial.print(F("  HR:   "));
  Serial.println(statusToString(hrStatus));
  Serial.print(F("  GSR:  "));
  Serial.println(statusToString(gsrStatus));
  Serial.print(F("  Temp: "));
  Serial.println(statusToString(tempStatus));
  Serial.print(F("  IMU:  "));
  Serial.print(statusToString(mpuStatus));
  Serial.println(mpuCalibrated ? F(" [CALIBRATED]") : F(" [NOT CALIBRATED]"));

  Serial.println(F("\nStress Model (v4.1 — Edge + Client):"));
  Serial.print(F("  Edge: "));
  Serial.println(F("Feature extraction + baseline calibration"));
  Serial.print(F("  Client: "));
  Serial.println(F("Classification by mobile app"));
  Serial.print(F("  Baseline: "));
  Serial.println(baseline.calibrated ? "CALIBRATED" : "PENDING");
  if (baseline.calibrated) {
    Serial.print(F("  EDA baseline: "));
    Serial.print(baseline.edaMean, 2);
    Serial.print(F(" +/- "));
    Serial.print(baseline.edaStd, 2);
    Serial.println(F(" uS"));
    Serial.print(F("  Temp baseline: "));
    Serial.print(baseline.tempMean, 2);
    Serial.print(F(" +/- "));
    Serial.print(baseline.tempStd, 2);
    Serial.println(F(" C"));
    Serial.print(F("  HR baseline: "));
    Serial.print(baseline.hrMean, 1);
    Serial.print(F(" +/- "));
    Serial.print(baseline.hrStd, 1);
    Serial.println(F(" bpm"));
    Serial.print(F("  RMSSD baseline: "));
    Serial.print(baseline.rmssdMean, 1);
    Serial.print(F(" +/- "));
    Serial.print(baseline.rmssdStd, 1);
    Serial.println(F(" ms"));
  }
  Serial.print(F("  Window buffers: EDA="));
  Serial.print(edaWindow.count);
  Serial.print(F("/"));
  Serial.print(EDA_WINDOW_SIZE);
  Serial.print(F("  Temp="));
  Serial.print(tempWindow.count);
  Serial.print(F("/"));
  Serial.print(TEMP_WINDOW_SIZE);
  Serial.print(F("  Acc="));
  Serial.print(accMagWindow.count);
  Serial.print(F("/"));
  Serial.print(ACC_WINDOW_SIZE);
  Serial.print(F("  IBI="));
  Serial.print(ibiWindow.count);
  Serial.print(F("/"));
  Serial.println(IBI_WINDOW_SIZE);

  Serial.println(F("\nBLE:"));
  Serial.print(F("  Status: "));
  Serial.println(bleDeviceConnected ? "Connected" : "Advertising");

  Serial.println(F("\nIMU Calibration (v3.9):"));
  Serial.print(F("  DLPF: CFG=3 (Accel BW=44Hz, Gyro BW=42Hz)"));
  Serial.println(F("  SampleRate: 200Hz (div=4)"));
  Serial.print(F("  Gyro HW offsets: X="));
  Serial.print(mpuGyroOffsetX);
  Serial.print(F(" Y="));
  Serial.print(mpuGyroOffsetY);
  Serial.print(F(" Z="));
  Serial.println(mpuGyroOffsetZ);
  Serial.print(F("  Accel SW offsets: X="));
  Serial.print(mpuAccelOffsetX);
  Serial.print(F(" Y="));
  Serial.print(mpuAccelOffsetY);
  Serial.print(F(" Z="));
  Serial.println(mpuAccelOffsetZ);
  Serial.print(F("  Accel range: +/-2g (16384 LSB/g)"));
  Serial.println(F("  Gyro range: +/-250dps (131 LSB/dps)"));

  Serial.println(F("\nTemp Pipeline (v3.8.3):"));
  Serial.print(F("  EEPROM emissivity: "));
  float readEpsilon = readMLX90614Emissivity();
  if (readEpsilon > 0) {
    Serial.print(readEpsilon, 4);
    Serial.print(F(" (target: "));
    Serial.print(skinEmissivity, 3);
    Serial.print(F(")"));
    if (fabs(readEpsilon - skinEmissivity) < 0.005)
      Serial.println(F(" OK"));
    else
      Serial.println(F(" MISMATCH!"));
  } else
    Serial.println(F("READ ERROR"));
  Serial.print(F("  Amb compensation: k="));
  Serial.print(TEMP_AMB_COEFF, 2);
  Serial.print(F(", ref="));
  Serial.print(TEMP_AMB_REF, 0);
  Serial.println(F("C"));
  Serial.println(F("  Filter: MLX(emiss) -> AmbComp -> Median5 -> "
                   "LinCal(833pt) -> OutlierGate -> DualEMA -> RateLim"));
  Serial.print(F("  Fast EMA (a="));
  Serial.print(MLX_EMA_FAST_ALPHA, 2);
  Serial.print(F("): "));
  Serial.println(tempEmaFast, 2);
  Serial.print(F("  Slow EMA (a="));
  Serial.print(MLX_EMA_SLOW_ALPHA, 2);
  Serial.print(F("): "));
  Serial.println(tempEmaSlow, 2);
  Serial.print(F("  Outlier gate: "));
  Serial.print(MLX_OUTLIER_THRESHOLD, 1);
  Serial.println(F("C"));
  Serial.print(F("  Rate limiter: "));
  Serial.print(TEMP_MAX_RATE_PER_SEC, 2);
  Serial.println(F("C/sec"));
  Serial.print(F("  LinCal: "));
  Serial.print(TEMP_CAL_SLOPE, 4);
  Serial.print(F("*x + "));
  Serial.println(TEMP_CAL_INTERCEPT, 4);
  Serial.print(F("  Fine-tune: "));
  Serial.print(tempFineTuneOffset, 2);
  Serial.println(F("C"));
  Serial.print(F("  Output: "));
  Serial.print(currentTempCalibrated, 2);
  Serial.println(F("C"));

  Serial.print(F("\nWorn: "));
  Serial.println(deviceWorn ? "YES" : "NO");
  Serial.print(F("Bat: "));
  Serial.print(batteryVoltageSmoothed, 2);
  Serial.print(F("V ("));
  Serial.print(batteryPercent);
  Serial.println(F("%)"));
  Serial.println(F("=====================================\n"));
}
