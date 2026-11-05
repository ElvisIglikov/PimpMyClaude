#pragma once
#include <stdbool.h>
#include <stdint.h>
bool NWKeyboardOpen(void);
uint64_t NWKeyboardID(void);
float NWBrightness(void);
bool NWAutoBrightness(void);
double NWIdleTimeout(void);
bool NWSetBrightness(float brightness, int fadeMilliseconds);
bool NWSetAutoBrightness(bool enabled);
bool NWPWMAvailable(void);
double NWPWMHigh(void);
bool NWPWMEnabled(void);
double NWIdleSeconds(void);
