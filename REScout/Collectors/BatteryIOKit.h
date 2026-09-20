#ifndef BatteryIOKit_h
#define BatteryIOKit_h

#include <stdbool.h>

typedef struct DOVBatteryExtras {
    int has_voltage;
    int voltage_mV;
    int has_amperage;
    int amperage_mA;
    int has_temperature;
    double temperature_C;
    int has_cycle_count;
    int cycle_count;
    int has_design_capacity;
    int design_capacity_mAh;
    int has_max_capacity;
    int max_capacity_mAh;
    int has_current_capacity;
    int current_capacity_mAh;
    int has_health;
    int health_percent;
    int has_serial;
    char serial[96];
} DOVBatteryExtras;

/// Returns 1 if at least one field was populated.
int DOVCopyBatteryExtras(DOVBatteryExtras *out);

#endif /* BatteryIOKit_h */
