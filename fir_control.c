#include <stdint.h>

// Memory-mapped register definitions
#define reg_fir_control (*(volatile uint32_t*)0x30000000)
#define reg_fir_coeff   (*(volatile uint32_t*)0x30000080)
#define reg_fir_x       (*(volatile uint32_t*)0x30000040)
#define reg_fir_y       (*(volatile uint32_t*)0x30000044)
#define reg_mprj_data1  (*(volatile uint32_t*)0x20000000)  // Example address, adjust as needed

// FIR Control Register bits
#define FIR_START   0
#define FIR_DONE    1
#define FIR_IDLE    2
#define FIR_X_READY 4
#define FIR_Y_READY 5

// Test parameters
#define NUM_ITERATIONS  3
#define DATA_LENGTH     64  // Example length, adjust as needed

// FIR coefficients (example values)
const int32_t fir_coeffs[] = {0, -10, -9, 23, 56, 63, 56, 23, -9, -10, 0};
#define NUM_TAPS (sizeof(fir_coeffs)/sizeof(fir_coeffs[0])

// Test data (example input values)
const int32_t input_data[DATA_LENGTH] = {
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
};

void program_fir_coefficients() {
    for (int i = 0; i < NUM_TAPS; i++) {
        *(volatile uint32_t*)(0x30000080 + i*4) = fir_coeffs[i];
    }
    
    // Set data length
    *(volatile uint32_t*)0x30000010 = DATA_LENGTH;
    
    // Set number of taps
    *(volatile uint32*)0x30000014 = NUM_TAPS;
}

void wait_for_fir_ready() {
    while (!(reg_fir_control & (1 << FIR_X_READY))) {
        // Wait until FIR is ready to accept new input
    }
}

void wait_for_fir_output() {
    while (!(reg_fir_control & (1 << FIR_Y_READY))) {
        // Wait until FIR has output ready
    }
}

int main() {
    uint32_t total_latency = 0;
    
    // 1. Initialization
    configure_mprj_pins();
    
    for (int iter = 0; iter < NUM_ITERATIONS; iter++) {
        // 2. Program coefficients and length
        program_fir_coefficients();
        
        // 3. Send StartMark
        reg_mprj_data1 = 0x00A50000;
        
        // Start latency timer
        uint32_t start_time = read_timer();
        
        // 4. Process all data
        for (int i = 0; i < DATA_LENGTH; i++) {
            wait_for_fir_ready();
            reg_fir_x = input_data[i];
            wait_for_fir_output();
            int32_t output = reg_fir_y;
        }
        
        // 7. Send final output and EndMark
        uint32_t final_output = reg_fir_y;
        reg_mprj_data1 = (final_output << 24) | 0x005A0000;
        
        // Record latency
        uint32_t end_time = read_timer();
        uint32_t latency = end_time - start_time;
        total_latency += latency;

    }
    return 0;
}