#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

// Memory-mapped register definitions
#define reg_fir_control (*(volatile uint32_t*)0x30000000)
#define reg_fir_coeff   (*(volatile uint32_t*)0x30000080)
#define reg_fir_x       (*(volatile uint32_t*)0x30000040)
#define reg_fir_y       (*(volatile uint32_t*)0x30000044)
#define reg_mprj_data1  (*(volatile uint32_t*)0x20000000)

// FIR Control Register bits
#define FIR_START   0
#define FIR_DONE    1
#define FIR_IDLE    2
#define FIR_X_READY 4
#define FIR_Y_READY 5

// Test parameters
#define NUM_ITERATIONS 3
#define DATA_LENGTH 256

// FIR coefficients (from your implementation)
const int32_t fir_coeffs[] = {0,-10,-9,23,56,63,56,23,-9,-10,0};
#define NUM_TAPS (sizeof(fir_coeffs)/sizeof(fir_coeffs[0]))

// Function prototypes
void configure_mprj_pins();
void program_fir_coefficients();
void wait_for_fir_ready();
void wait_for_fir_output();
void load_test_data(const char* filename, int32_t* buffer, int max_length);
int compare_results(const int32_t* actual, const int32_t* expected, int length);

int main() {
    int32_t input_data[DATA_LENGTH];
    int32_t golden_output[DATA_LENGTH];
    
    load_test_data("samples_triangular_wave.txt", input_data, DATA_LENGTH);
    load_test_data("out_gold.txt", golden_output, DATA_LENGTH);

    uint32_t total_latency = 0;
    int test_passed = 1;
    
    configure_mprj_pins();
    
    for (int iter = 0; iter < NUM_ITERATIONS; iter++) {
        printf("Starting iteration %d...\n", iter+1);
        
        program_fir_coefficients();
        
        reg_mprj_data1 = 0x00A50000;
        printf("Sent StartMark (0xA5)\n");
        
        uint32_t start_time = 0;
        
        int32_t actual_output[DATA_LENGTH];
        
        for (int i = 0; i < DATA_LENGTH; i++) {
            wait_for_fir_ready();

            reg_fir_x = input_data[i];
            
            wait_for_fir_output();
            
            actual_output[i] = reg_fir_y;
            
            if ((i+1) % 32 == 0) {
                printf("Processed %d/%d samples...\n", i+1, DATA_LENGTH);
            }
        }
        
        // Verify results
        int errors = compare_results(actual_output, golden_output, DATA_LENGTH);
        if (errors > 0) {
            printf("ERROR: Iteration %d failed with %d mismatches!\n", iter+1, errors);
            test_passed = 0;
        } else {
            printf("Iteration %d passed verification\n", iter+1);
        }
        
        uint32_t final_output = actual_output[DATA_LENGTH-1];
        reg_mprj_data1 = (final_output << 24) | 0x005A0000;
        printf("Sent EndMark (0x5A) with final output: %d\n", final_output);
        
        uint32_t end_time = 0; // Replace with actual timer read
        uint32_t latency = end_time - start_time;
        total_latency += latency;
        printf("Iteration %d latency: %u cycles\n", iter+1, latency);
    }
    
    printf("\n=== Test Summary ===\n");
    printf("Total latency across %d iterations: %u cycles\n", NUM_ITERATIONS, total_latency);
    printf("Average latency: %u cycles\n", total_latency/NUM_ITERATIONS);
    
    if (test_passed) {
        printf("TEST PASSED - All iterations matched golden output\n");
        return 0;
    } else {
        printf("TEST FAILED - Some iterations had output mismatches\n");
        return 1;
    }
}

void program_fir_coefficients() {
    for (int i = 0; i < NUM_TAPS; i++) {
        *(volatile uint32_t*)(0x30000080 + i*4) = fir_coeffs[i];
    }
    
    *(volatile uint32_t*)0x30000010 = DATA_LENGTH;
    *(volatile uint32_t*)0x30000014 = NUM_TAPS;
}

void wait_for_fir_ready() {
    while (!(reg_fir_control & (1 << FIR_X_READY))) {
    }
}

void wait_for_fir_output() {
    while (!(reg_fir_control & (1 << FIR_Y_READY))) {
    }
}

void load_test_data(const char* filename, int32_t* buffer, int max_length) {
    FILE* file = fopen(filename, "r");
    if (!file) {
        printf("ERROR: Could not open file %s\n", filename);
        exit(1);
    }
    
    int count = 0;
    while (count < max_length && fscanf(file, "%d", &buffer[count]) == 1) {
        count++;
    }
    
    fclose(file);
    
    if (count != max_length) {
        printf("WARNING: Only read %d values from %s (expected %d)\n", 
               count, filename, max_length);
    } else {
        printf("Successfully loaded %d values from %s\n", count, filename);
    }
}

int compare_results(const int32_t* actual, const int32_t* expected, int length) {
    int errors = 0;
    int max_errors_to_print = 10;
    
    for (int i = 0; i < length; i++) {
        if (actual[i] != expected[i]) {
            if (errors < max_errors_to_print) {
                printf("Mismatch at sample %d: expected %d, got %d\n", 
                       i, expected[i], actual[i]);
            }
            errors++;
        }
    }
    
    if (errors > max_errors_to_print) {
        printf("... and %d more errors\n", errors - max_errors_to_print);
    }
    
    return errors;
}